import AppKit
import SwiftUI

/// Cached notch-related metrics so geometry-only edits can avoid a full SwiftUI rebuild.
struct NotchRenderMetrics: Equatable {
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let screenWidth: CGFloat
}

/// Layout, geometry, and screen-hop behavior for the panel window controller.
@MainActor
extension PanelWindowController {
    private func panelSize(for screen: NSScreen) -> NSSize {
        let screenWidth = screen.frame.width
        let width = min(620, screenWidth - 40)
        let collapsedHeight = max(resolvedNotchHeight(for: screen) + 8, 38)

        guard appState.surface.isExpanded else {
            return NSSize(width: width, height: collapsedHeight)
        }

        let maxSessions = CGFloat(max(2, UserDefaults.standard.integer(forKey: SettingsKey.maxVisibleSessions)))
        let maxPanelHeight = CGFloat(max(220, SettingsManager.shared.maxPanelHeight))
        let detailEstimatedHeight = sessionDetailEstimatedHeight()
        let height = Self.expandedPanelHeight(
            surface: appState.surface,
            collapsedHeight: collapsedHeight,
            maxPanelHeight: maxPanelHeight,
            screenHeight: screen.frame.height,
            maxVisibleSessions: maxSessions,
            detailEstimatedHeight: detailEstimatedHeight
        )
        return NSSize(width: width, height: height)
    }

    /// Session detail should be taller than the compact list, but keep it noticeably tighter
    /// than approval/list surfaces so short transcripts do not feel vertically bloated.
    nonisolated static func expandedPanelHeight(
        surface: IslandSurface,
        collapsedHeight: CGFloat,
        maxPanelHeight: CGFloat,
        screenHeight: CGFloat,
        maxVisibleSessions: CGFloat,
        detailEstimatedHeight: CGFloat? = nil
    ) -> CGFloat {
        let estimatedHeight: CGFloat
        switch surface {
        case .sessionDetail, .completionCard:
            estimatedHeight = detailEstimatedHeight
                ?? SessionDetailLayoutMetrics.estimatedPanelHeight(session: nil, conversationState: nil)
        case .approvalCard, .questionCard, .sessionList:
            let listViewportHeight = SessionListView.notchScrollHeight(
                maxVisibleSessions: Int(maxVisibleSessions.rounded(.up))
            )
            // Leave room for the divider plus expanded-surface top/bottom insets so
            // the first list row is fully visible below the notch shell.
            estimatedHeight = max(300, listViewportHeight + 76)
        case .collapsed:
            estimatedHeight = collapsedHeight
        }

        // Session detail should never grow beyond half of the current screen height,
        // even if the user's global panel cap is larger.
        let effectiveMaxPanelHeight: CGFloat
        switch surface {
        case .sessionDetail, .completionCard:
            effectiveMaxPanelHeight = SessionDetailLayoutMetrics.maxDetailPanelHeight(
                maxPanelHeight: maxPanelHeight,
                screenHeight: screenHeight
            )
        case .approvalCard, .questionCard, .sessionList, .collapsed:
            effectiveMaxPanelHeight = maxPanelHeight
        }

        return min(effectiveMaxPanelHeight, max(collapsedHeight, estimatedHeight))
    }

    /// Use parsed transcript state when available so the panel can adapt after the detail view loads real history.
    private func sessionDetailEstimatedHeight() -> CGFloat? {
        let sessionId: String
        switch appState.surface {
        case .sessionDetail(let activeSessionId), .completionCard(let activeSessionId):
            sessionId = activeSessionId
        default:
            return nil
        }
        let session = appState.sessions[sessionId]
        let conversationState = ChatHistoryManager.shared.state(for: sessionId)
        return SessionDetailLayoutMetrics.estimatedPanelHeight(
            session: session,
            conversationState: conversationState
        )
    }

    /// Runtime sizing always follows the currently selected screen.
    var panelSize: NSSize {
        panelSize(for: chosenScreen())
    }

    /// Build a fresh hosting view whenever notch metrics or the target screen change.
    func makeHostingView(for screen: NSScreen) -> NotchHostingView<NotchPanelView> {
        let metrics = renderMetrics(for: screen)
        let rootView = NotchPanelView(
            appState: appState,
            hasNotch: metrics.hasNotch,
            notchHeight: metrics.notchHeight,
            notchW: metrics.notchWidth,
            screenWidth: metrics.screenWidth
        )

        let contentView = NotchHostingView(rootView: rootView)
        contentView.isExpanded = { [weak self] in
            self?.appState.surface.isExpanded ?? false
        }
        contentView.collapsedInteractiveHeight = {
            metrics.notchHeight
        }
        contentView.sizingOptions = []
        contentView.translatesAutoresizingMaskIntoConstraints = true
        return contentView
    }

    /// Rebuild the SwiftUI tree when screen-dependent notch metrics are materially different.
    func rebuildForCurrentScreen(_ screen: NSScreen) {
        guard let panel else { return }
        let contentView = makeHostingView(for: screen)
        hostingView = contentView
        installHostingView(contentView, in: panel)
        lastRenderMetrics = renderMetrics(for: screen)
        lastChosenScreenSignature = ScreenDetector.signature(for: screen)
        syncWindowInteractionBehavior()
        updatePosition()
        reconcilePointerHoverState()
    }

    /// Wrap the hosting view in a plain container so the window has more than one view.
    /// This works around a SwiftUI/AppKit bug where a single-view window throws
    /// "more Update Constraints in Window passes than there are views" during animated resizes.
    func installHostingView(_ hostingView: NotchHostingView<NotchPanelView>, in panel: NSPanel) {
        if let container = panel.contentView, !(container is NotchHostingView<NotchPanelView>) {
            for subview in container.subviews {
                subview.removeFromSuperview()
            }
            hostingView.frame = container.bounds
            hostingView.autoresizingMask = [.width, .height]
            container.addSubview(hostingView)
        } else {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = true
            hostingView.frame = container.bounds
            hostingView.autoresizingMask = [.width, .height]
            container.addSubview(hostingView)
            panel.contentView = container
        }
    }

    /// Screen preference changes animate only when the chosen display actually changes.
    func refreshCurrentScreen(forceRebuild: Bool = false) {
        if isAnimatingScreenHop { return }

        let screen = chosenScreen()
        let signature = ScreenDetector.signature(for: screen)

        if forceRebuild {
            rebuildForCurrentScreen(screen)
            return
        }

        if signature != lastChosenScreenSignature {
            animateScreenHop(to: screen, signature: signature)
        }
    }

    /// Fade-out, rebuild, and fade-in creates a cleaner display hop than snapping between screens.
    func animateScreenHop(to screen: NSScreen, signature: String) {
        guard let panel else {
            rebuildForCurrentScreen(screen)
            return
        }

        if !panel.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            rebuildForCurrentScreen(screen)
            panel.alphaValue = 1
            return
        }

        isAnimatingScreenHop = true
        let oldFrame = panel.frame
        let newFrame = panelFrame(for: screen)
        let motion = Self.screenHopMotion()
        let frames = Self.screenHopFrames(oldFrame: oldFrame, newFrame: newFrame)
        let targetSignature = signature

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(frames.outgoing, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let panel = self.panel else {
                    self.isAnimatingScreenHop = false
                    return
                }

                let targetScreen = NSScreen.screens.first {
                    ScreenDetector.signature(for: $0) == targetSignature
                } ?? self.chosenScreen()

                self.rebuildForCurrentScreen(targetScreen)
                panel.alphaValue = 0
                panel.setFrame(frames.incoming, display: true)

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(motion.incomingPauseDuration * 1_000_000_000))
                    guard let self = self else { return }
                    guard let panel = self.panel else {
                        self.isAnimatingScreenHop = false
                        return
                    }

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = motion.fadeInDuration
                        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                        panel.animator().alphaValue = 1
                        panel.animator().setFrame(newFrame, display: true)
                    } completionHandler: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.lastChosenScreenSignature = targetSignature
                            self?.isAnimatingScreenHop = false
                        }
                    }
                }
            }
        }
    }

    func updatePosition() {
        guard let panel else { return }
        panel.setFrame(panelFrame(for: chosenScreen()), display: true)
    }

    /// Skip redundant frame writes to reduce needless AppKit work during screen polling.
    func updatePositionIfNeeded() {
        guard let panel else { return }
        let targetFrame = panelFrame(for: chosenScreen())
        guard !PanelGeometry.approximatelyEqual(panel.frame, targetFrame) else { return }
        panel.setFrame(targetFrame, display: true)
    }

    /// Panel placement stays centered on the notch unless the user enabled horizontal drag.
    func panelFrame(for screen: NSScreen) -> NSRect {
        let geometry = resolvedNotchGeometry(for: screen)
        return PanelGeometry.panelFrame(
            panelSize: panelSize(for: screen),
            screenFrame: screen.frame,
            allowHorizontalDrag: SettingsManager.shared.allowHorizontalDrag,
            storedHorizontalOffset: geometry.horizontalOffset
        )
    }

    /// Respect per-screen offsets but clamp them for the current display width.
    func resolvedNotchGeometry(for screen: NSScreen) -> ScreenNotchGeometry {
        let stored = NotchCustomizationStore.shared.customization.geometry(for: screen.notchScreenID)
        var resolved = stored
        resolved.horizontalOffset = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: stored.horizontalOffset,
            runtimeWidth: panelSize(for: screen).width,
            screenFrame: screen.frame
        )
        return resolved
    }

    /// Virtual notch mode owns height; physical notch mode defers to measured menu-bar geometry.
    func resolvedNotchHeight(for screen: NSScreen) -> CGFloat {
        if SettingsManager.shared.hardwareNotchMode == .forceVirtual {
            let storedHeight = NotchCustomizationStore.shared.customization.geometry(for: screen.notchScreenID).notchHeight
            return NotchHardwareDetector.clampedHeight(storedHeight)
        }
        return ScreenDetector.topBarHeight(for: screen)
    }

    /// Cached render metrics are used to decide whether a notch edit requires a full rebuild.
    func renderMetrics(for screen: NSScreen) -> NotchRenderMetrics {
        NotchRenderMetrics(
            hasNotch: ScreenDetector.screenHasNotch(screen),
            notchHeight: resolvedNotchHeight(for: screen),
            notchWidth: ScreenDetector.notchWidth(for: screen),
            screenWidth: screen.frame.width
        )
    }

    /// Respect persisted screen selection before falling back to the auto-detected preferred screen.
    func chosenScreen() -> NSScreen {
        ScreenSelector.shared.selectedScreen ?? ScreenDetector.preferredScreen
    }
}
