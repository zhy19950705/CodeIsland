import AppKit
import ApplicationServices
import SwiftUI

/// Interaction, visibility, live-edit, and fullscreen behavior for the panel window controller.
@MainActor
extension PanelWindowController {
    /// Horizontal dragging persists an offset relative to the centered default position.
    func setupHorizontalDragMonitor() {
        let newMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel,
                  SettingsManager.shared.allowHorizontalDrag else { return event }

            switch event.type {
            case .leftMouseDown:
                if event.window === panel {
                    self.dragStartMouseX = NSEvent.mouseLocation.x
                    self.dragStartPanelX = panel.frame.origin.x
                    self.isDraggingPanel = false
                }
            case .leftMouseDragged:
                if let startMouseX = self.dragStartMouseX,
                   let startPanelX = self.dragStartPanelX {
                    let deltaX = NSEvent.mouseLocation.x - startMouseX
                    if !self.isDraggingPanel {
                        guard PanelGeometry.shouldStartDrag(deltaX: deltaX) else { return event }
                        self.isDraggingPanel = true
                    }
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    panel.setFrameOrigin(
                        PanelGeometry.draggedFrameOrigin(
                            startPanelX: startPanelX,
                            mouseDeltaX: deltaX,
                            panelSize: size,
                            screenFrame: screen.frame
                        )
                    )
                }
            case .leftMouseUp:
                if self.isDraggingPanel, let panel = self.panel {
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    let offset = PanelGeometry.persistedHorizontalOffset(
                        panelOriginX: panel.frame.origin.x,
                        panelWidth: size.width,
                        screenFrame: screen.frame
                    )
                    SettingsManager.shared.panelHorizontalOffset = Double(offset)
                    NotchCustomizationStore.shared.updateGeometry(for: screen.notchScreenID) { geometry in
                        geometry.horizontalOffset = offset
                    }
                }
                self.dragStartMouseX = nil
                self.dragStartPanelX = nil
                self.isDraggingPanel = false
            default:
                break
            }
            return event
        }

        Self.replaceMonitor(
            currentMonitor: &localDragMonitor,
            newMonitor: newMonitor,
            removeMonitor: NSEvent.removeMonitor
        )
    }

    /// Visibility combines display mode, fullscreen policy, and session presence.
    func updateVisibility() {
        guard let panel else { return }
        syncAutomaticActivationMode()
        syncWindowInteractionBehavior()

        guard shouldShowPanel(on: chosenScreen()) else {
            panel.orderOut(nil)
            return
        }

        let settings = SettingsManager.shared
        if settings.hideInFullscreen && environmentMonitor.fullscreenLatch {
            panel.orderOut(nil)
            return
        }

        if SessionVisibilityPolicy.shouldHideWhenNoSession(
            hideWhenNoSession: settings.hideWhenNoSession,
            sessions: appState.sessions
        ) {
            panel.orderOut(nil)
            return
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// Observe live customization so geometry edits can update the panel immediately.
    func startNotchCustomizationObserversIfNeeded() {
        guard notchCustomizationObserver == nil, notchEditingObserver == nil else { return }

        notchCustomizationObserver = NotificationCenter.default.addObserver(
            forName: .superIslandNotchCustomizationDidChange,
            object: NotchCustomizationStore.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let screen = self.chosenScreen()
                let metrics = self.renderMetrics(for: screen)
                if self.lastRenderMetrics != metrics {
                    self.rebuildForCurrentScreen(screen)
                } else {
                    self.updatePosition()
                }
            }
        }

        notchEditingObserver = NotificationCenter.default.addObserver(
            forName: .superIslandNotchEditingDidChange,
            object: NotchCustomizationStore.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncLiveEditMode()
            }
        }
    }

    /// The overlay panel is driven entirely from the store's editing flag.
    func syncLiveEditMode() {
        if NotchCustomizationStore.shared.isEditing {
            enterLiveEditMode()
        } else {
            exitLiveEditMode()
        }
    }

    /// Live edit floats above the target display while keeping the main panel visible for preview.
    func enterLiveEditMode() {
        guard liveEditPanel == nil else { return }

        let screen = chosenScreen()
        wasPanelVisibleBeforeLiveEdit = panel?.isVisible ?? false
        showPanel()

        let overlayPanel = NotchLiveEditPanel(screen: screen)
        let hostingView = NSHostingView(
            rootView: NotchLiveEditOverlay(
                screenID: screen.notchScreenID,
                onSave: { [weak self] in
                    NotchCustomizationStore.shared.commitEdit()
                    self?.refreshCurrentScreen(forceRebuild: true)
                },
                onCancel: { [weak self] in
                    NotchCustomizationStore.shared.cancelEdit()
                    self?.refreshCurrentScreen(forceRebuild: true)
                }
            )
        )
        hostingView.frame = overlayPanel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        overlayPanel.contentView?.addSubview(hostingView)
        overlayPanel.orderFrontRegardless()
        liveEditPanel = overlayPanel
    }

    /// Closing live edit restores the previous menu-bar visibility state when needed.
    func exitLiveEditMode() {
        liveEditPanel?.orderOut(nil)
        liveEditPanel?.close()
        liveEditPanel = nil

        if !wasPanelVisibleBeforeLiveEdit, currentResolvedMode() == .menuBar {
            hidePanel()
        }
    }

    /// Closed state stays below menus; open states rise above menu-bar items for reliable clicks.
    func syncWindowInteractionBehavior() {
        guard let panel = panel as? KeyablePanel else { return }
        let presentationStatus = appState.presentationState.status

        panel.ignoresMouseEvents = Self.shouldIgnoreMouseEvents(
            for: presentationStatus,
            supportsBackgroundPointerTracking: Self.supportsBackgroundPointerTracking()
        )

        switch presentationStatus {
        case .closed:
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            panel.allowsInteractiveActivation = false
        case .opened, .popping:
            panel.level = .popUpMenu
            panel.allowsInteractiveActivation = shouldActivateWindow(for: appState.lastOpenReason)
        }
    }

    /// Closed panels should be visually present but pointer-transparent so menu-bar
    /// interactions keep working until the hover controller deliberately opens them.
    nonisolated static func shouldIgnoreMouseEvents(
        for status: IslandPresentationStatus,
        supportsBackgroundPointerTracking: Bool
    ) -> Bool {
        switch status {
        case .closed:
            // Closed mode should stay click-through when global pointer tracking
            // is available, matching the notch-overlay behavior in the reference apps.
            return supportsBackgroundPointerTracking
        case .opened, .popping:
            return false
        }
    }

    /// Background pointer tracking depends on Accessibility trust because closed-state
    /// reopening is driven by global mouse monitors rather than SwiftUI hover.
    nonisolated static func supportsBackgroundPointerTracking() -> Bool {
        AXIsProcessTrusted()
    }

    /// Only explicit direct interactions should focus the panel while background notifications stay passive.
    func shouldActivateWindow(for reason: IslandOpenReason) -> Bool {
        switch reason {
        case .click, .pinned, .shortcut, .deeplink:
            return true
        case .hover, .notification, .boot, .unknown:
            return NSApp.isActive
        }
    }

    /// Automatic updates remain passive when SuperIsland is not frontmost.
    func syncAutomaticActivationMode() {
        guard let panel = panel as? KeyablePanel else { return }
        if appState.presentationState.status == .closed {
            panel.allowsInteractiveActivation = false
            return
        }
        panel.allowsInteractiveActivation = Self.automaticPresentationActivationMode(appIsActive: NSApp.isActive)
            && shouldActivateWindow(for: appState.lastOpenReason)
    }

    /// The panel is suppressed entirely when the resolved display mode is menu-bar only.
    func shouldShowPanel(on screen: NSScreen) -> Bool {
        Self.resolvedPresentationMode(
            displayMode: SettingsManager.shared.displayMode,
            hasPhysicalNotch: ScreenDetector.screenHasNotch(screen),
            screenCount: max(ScreenSelector.shared.availableScreens.count, 1),
            forceVirtualNotch: SettingsManager.shared.hardwareNotchMode == .forceVirtual
        ) != .menuBar
    }

    /// Resolve using the currently selected display and virtual-notch preference.
    func currentResolvedMode() -> DisplayMode {
        let screen = chosenScreen()
        return Self.resolvedPresentationMode(
            displayMode: SettingsManager.shared.displayMode,
            hasPhysicalNotch: ScreenDetector.screenHasNotch(screen),
            screenCount: max(ScreenSelector.shared.availableScreens.count, 1),
            forceVirtualNotch: SettingsManager.shared.hardwareNotchMode == .forceVirtual
        )
    }

    nonisolated static func resolvedPresentationMode(
        displayMode: DisplayMode,
        hasPhysicalNotch: Bool,
        screenCount: Int,
        forceVirtualNotch: Bool = false
    ) -> DisplayMode {
        DisplayModeCoordinator.resolveMode(
            displayMode,
            hasPhysicalNotch: hasPhysicalNotch,
            screenCount: screenCount,
            forceVirtualNotch: forceVirtualNotch
        )
    }

    /// Fullscreen detection is always scoped to the currently selected screen.
    func isActiveSpaceFullscreen() -> Bool {
        FullscreenAppDetector.isFullscreenAppActive(screenFrame: chosenScreen().frame)
    }

    /// Edge reveal is only used for fullscreen flows on displays without a physical notch.
    func isMouseInFullscreenRevealZone(
        panelWidth: CGFloat,
        notchWidth: CGFloat,
        hasNotch: Bool
    ) -> Bool {
        guard !hasNotch,
              SettingsManager.shared.hideInFullscreen,
              isFullscreenEdgeRevealActive else { return false }

        let settings = SettingsManager.shared
        let zoneWidth = panelWidth + (settings.fullscreenRevealZoneHorizontalInset * 2)
        let zoneRect = CGRect(
            x: chosenScreen().frame.midX - zoneWidth / 2,
            y: chosenScreen().frame.maxY - settings.fullscreenRevealZoneHeight,
            width: zoneWidth,
            height: settings.fullscreenRevealZoneHeight
        )
        return zoneRect.contains(NSEvent.mouseLocation)
    }

    /// Edge reveal toggles as fullscreen state changes and collapses the island when entering reveal mode.
    func updateFullscreenEdgeRevealState() {
        let shouldUseEdgeReveal = SettingsManager.shared.hideInFullscreen
            && !ScreenDetector.screenHasNotch(chosenScreen())
            && isActiveSpaceFullscreen()

        guard shouldUseEdgeReveal != isFullscreenEdgeRevealActive else { return }
        isFullscreenEdgeRevealActive = shouldUseEdgeReveal

        if shouldUseEdgeReveal, appState.surface.isExpanded {
            withAnimation(NotchAnimation.close) {
                appState.surface = .collapsed
            }
        }
    }

    /// Fast foreground check avoids AppleScript or subprocess work on the hot path.
    func isActiveTerminalForeground() -> Bool {
        guard let sessionId = appState.activeSessionId,
              let session = appState.sessions[sessionId],
              session.termApp != nil else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    func windowDidMove(_ notification: Notification) {
        // Drag is handled by setupHorizontalDragMonitor — no correction needed here.
    }
}

extension Notification.Name {
    static let superIslandPanelStateDidChange = Notification.Name("SuperIslandPanelStateDidChange")
    static let superIslandSurfaceDidChange = Notification.Name("SuperIslandSurfaceDidChange")
}
