import AppKit
import SwiftUI
import os.log
import SuperIslandCore

private let log = Logger(subsystem: "com.superisland", category: "Panel")

private class KeyablePanel: NSPanel {
    /// Keep the panel passive by default so background completion cards do not
    /// steal focus from the app the user is actively typing into.
    var allowsInteractiveActivation = false

    override var canBecomeKey: Bool { allowsInteractiveActivation }
    override var canBecomeMain: Bool { allowsInteractiveActivation }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            // A direct click is an explicit user intent to interact with SuperIsland,
            // so it is safe to promote the panel to an active key window here.
            allowsInteractiveActivation = true
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            makeKeyAndOrderFront(nil)
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Ensures first click on a nonactivatingPanel fires SwiftUI actions
/// instead of being consumed for key-window activation.
/// Also guards against AppKit/SwiftUI layout re-entrancy when NSHostingView
/// invalidates constraints during an active display cycle.
private class NotchHostingView<Content: View>: NSHostingView<Content> {
    private var applyingDeferred = false
    private var pendingNeedsUpdateConstraints: Bool?
    private var pendingNeedsLayout: Bool?
    private var hasScheduledNeedsUpdateConstraints = false
    private var hasScheduledNeedsLayout = false

    override func mouseDown(with event: NSEvent) {
        // Only promote the panel when activation has already been allowed by an
        // explicit reveal or a direct click handled at the NSPanel level.
        if let panel = window as? KeyablePanel, panel.allowsInteractiveActivation {
            window?.makeKey()
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if applyingDeferred {
                super.needsUpdateConstraints = newValue
                return
            }
            pendingNeedsUpdateConstraints = newValue
            guard !hasScheduledNeedsUpdateConstraints else { return }
            hasScheduledNeedsUpdateConstraints = true
            DispatchQueue.main.async { [weak self] in
                self?.flushDeferredNeedsUpdateConstraints()
            }
        }
    }

    private func flushDeferredNeedsUpdateConstraints() {
        hasScheduledNeedsUpdateConstraints = false
        guard let pendingNeedsUpdateConstraints else { return }
        self.pendingNeedsUpdateConstraints = nil
        guard super.needsUpdateConstraints != pendingNeedsUpdateConstraints else { return }
        applySuperNeedsUpdateConstraints(pendingNeedsUpdateConstraints)
    }

    private func applySuperNeedsUpdateConstraints(_ value: Bool) {
        applyingDeferred = true
        super.needsUpdateConstraints = value
        applyingDeferred = false
    }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if applyingDeferred {
                super.needsLayout = newValue
                return
            }
            pendingNeedsLayout = newValue
            guard !hasScheduledNeedsLayout else { return }
            hasScheduledNeedsLayout = true
            DispatchQueue.main.async { [weak self] in
                self?.flushDeferredNeedsLayout()
            }
        }
    }

    private func flushDeferredNeedsLayout() {
        hasScheduledNeedsLayout = false
        guard let pendingNeedsLayout else { return }
        self.pendingNeedsLayout = nil
        guard super.needsLayout != pendingNeedsLayout else { return }
        applySuperNeedsLayout(pendingNeedsLayout)
    }

    private func applySuperNeedsLayout(_ value: Bool) {
        applyingDeferred = true
        super.needsLayout = value
        applyingDeferred = false
    }
}

struct PanelScreenHopFrames {
    let outgoing: NSRect
    let incoming: NSRect
}

struct PanelScreenHopMotion {
    let outgoingOffset: CGFloat
    let incomingOffset: CGFloat
    let fadeOutDuration: TimeInterval
    let incomingPauseDuration: TimeInterval
    let fadeInDuration: TimeInterval
}

@MainActor
class PanelWindowController: NSObject, NSWindowDelegate {
    private enum ScreenHopMetrics {
        static let outgoingOffset: CGFloat = 18
        static let incomingOffset: CGFloat = 30
        static let fadeOutDuration: TimeInterval = 0.14
        static let incomingPauseDuration: TimeInterval = 0.06
        static let fadeInDuration: TimeInterval = 0.34
    }

    nonisolated static func replaceMonitor(
        currentMonitor: inout Any?,
        newMonitor: Any?,
        removeMonitor: (Any) -> Void
    ) {
        if let currentMonitor {
            removeMonitor(currentMonitor)
        }
        currentMonitor = newMonitor
    }

    nonisolated static func screenHopMotion() -> PanelScreenHopMotion {
        PanelScreenHopMotion(
            outgoingOffset: ScreenHopMetrics.outgoingOffset,
            incomingOffset: ScreenHopMetrics.incomingOffset,
            fadeOutDuration: ScreenHopMetrics.fadeOutDuration,
            incomingPauseDuration: ScreenHopMetrics.incomingPauseDuration,
            fadeInDuration: ScreenHopMetrics.fadeInDuration
        )
    }

    private var panel: NSPanel?
    private var hostingView: NotchHostingView<NotchPanelView>?
    private let appState: AppState

    nonisolated static func screenHopFrames(
        oldFrame: NSRect,
        newFrame: NSRect
    ) -> PanelScreenHopFrames {
        let motion = screenHopMotion()
        return PanelScreenHopFrames(
            outgoing: oldFrame.offsetBy(dx: 0, dy: motion.outgoingOffset),
            incoming: newFrame.offsetBy(dx: 0, dy: motion.incomingOffset)
        )
    }

    private func panelSize(for screen: NSScreen) -> NSSize {
        let screenW = screen.frame.width
        let width = min(620, screenW - 40)
        let collapsedHeight = max(ScreenDetector.topBarHeight(for: screen) + 8, 38)

        guard appState.surface.isExpanded else {
            return NSSize(width: width, height: collapsedHeight)
        }

        let maxSessions = CGFloat(max(2, UserDefaults.standard.integer(forKey: SettingsKey.maxVisibleSessions)))
        let estimatedHeight = max(300, maxSessions * 90 + 60)
        let maxPanelHeight = CGFloat(max(220, SettingsManager.shared.maxPanelHeight))
        let height = min(maxPanelHeight, max(collapsedHeight, estimatedHeight))
        return NSSize(width: width, height: height)
    }

    private var panelSize: NSSize {
        panelSize(for: chosenScreen())
    }

    private let environmentMonitor = PanelEnvironmentMonitor()
    private var globalClickMonitor: Any?
    private var lastChosenScreenSignature = ""
    private var isAnimatingScreenHop = false
    private var dragStartMouseX: CGFloat?
    private var dragStartPanelX: CGFloat?
    private var isDraggingPanel = false
    private var localDragMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    nonisolated static func automaticPresentationActivationMode(appIsActive: Bool) -> Bool {
        // Automatic presentation must stay passive while SuperIsland is in the
        // background, otherwise the completion card can disrupt other apps.
        appIsActive
    }

    func showPanel() {
        if let panel {
            syncAutomaticActivationMode()
            updatePosition()
            updateVisibility()
            panel.orderFrontRegardless()
            return
        }

        ScreenSelector.shared.refreshScreens()
        let screen = chosenScreen()
        let contentView = makeHostingView(for: screen)
        self.hostingView = contentView

        let size = panelSize
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .readOnly
        panel.contentView = contentView
        panel.delegate = self

        self.panel = panel
        self.lastChosenScreenSignature = ScreenDetector.signature(for: screen)

        setupHorizontalDragMonitor()
        syncAutomaticActivationMode()
        updatePosition()
        panel.orderFrontRegardless()

        environmentMonitor.startObserving(
            appState: appState,
            handlers: PanelEnvironmentMonitor.Handlers(
                refreshCurrentScreen: { [weak self] forceRebuild in
                    self?.refreshCurrentScreen(forceRebuild: forceRebuild)
                },
                refreshAvailableScreens: {
                    ScreenSelector.shared.refreshScreens()
                },
                updateFullscreenEdgeRevealState: { [weak self] in
                    self?.updateFullscreenEdgeRevealState()
                },
                updateVisibility: { [weak self] in
                    self?.updateVisibility()
                },
                updatePosition: { [weak self] in
                    self?.updatePosition()
                },
                updatePositionIfNeeded: { [weak self] in
                    self?.updatePositionIfNeeded()
                },
                currentScreenSelectionPreference: {
                    ScreenSelector.shared.preferenceSignature
                },
                currentNotchWidthOverride: {
                    SettingsManager.shared.notchWidthOverride
                },
                currentSelectionMode: {
                    ScreenSelector.shared.selectionMode
                },
                isActiveSpaceFullscreen: { [weak self] in
                    self?.isActiveSpaceFullscreen() ?? false
                }
            )
        )

        // Replace the monitor defensively so panel recreation cannot stack duplicate global listeners.
        let newMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self = self, self.appState.surface.isExpanded else { return }
                // Don't close during approval/question
                switch self.appState.surface {
                case .approvalCard, .questionCard: return
                default: break
                }
                // Don't collapse if click is within the panel frame (event leaked on external display)
                if let panelFrame = self.panel?.frame {
                    let clickLocation = NSEvent.mouseLocation
                    if panelFrame.contains(clickLocation) { return }
                }
                withAnimation(NotchAnimation.close) {
                    self.appState.surface = .collapsed
                    self.appState.cancelCompletionQueue()
                }
            }
        }
        Self.replaceMonitor(
            currentMonitor: &globalClickMonitor,
            newMonitor: newMonitor,
            removeMonitor: NSEvent.removeMonitor
        )
    }

    func revealPanel() {
        guard let panel = panel as? KeyablePanel else { return }
        // Explicit reveal comes from a deliberate user action, so allow focus.
        panel.allowsInteractiveActivation = true
        NSApp.activate(ignoringOtherApps: true)
        updatePosition()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hidePanel() {
        if let panel = panel as? KeyablePanel {
            // Reset to passive mode before hiding so later automatic completion
            // cards do not inherit an earlier interactive activation state.
            panel.allowsInteractiveActivation = false
        }
        panel?.orderOut(nil)
    }

    private func makeHostingView(for screen: NSScreen) -> NotchHostingView<NotchPanelView> {
        let hasNotch = ScreenDetector.screenHasNotch(screen)
        let notchHeight = ScreenDetector.topBarHeight(for: screen)
        let notchW = ScreenDetector.notchWidth(for: screen)

        let rootView = NotchPanelView(
            appState: appState,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            notchW: notchW,
            screenWidth: screen.frame.width
        )
        let contentView = NotchHostingView(rootView: rootView)
        contentView.sizingOptions = []
        contentView.translatesAutoresizingMaskIntoConstraints = true
        return contentView
    }

    /// Rebuild the SwiftUI view when the target screen changes
    /// (notchHeight, notchWidth, hasNotch may be different)
    private func rebuildForCurrentScreen(_ screen: NSScreen) {
        guard let panel = panel else { return }
        let contentView = makeHostingView(for: screen)
        self.hostingView = contentView
        panel.contentView = contentView
        lastChosenScreenSignature = ScreenDetector.signature(for: screen)
        updatePosition()
    }

    private func refreshCurrentScreen(forceRebuild: Bool = false) {
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

    private func animateScreenHop(to screen: NSScreen, signature: String) {
        guard let panel = panel else {
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

    private func updatePosition() {
        guard let panel = panel else { return }
        let screen = chosenScreen()
        panel.setFrame(panelFrame(for: screen), display: true)
    }

    private func updatePositionIfNeeded() {
        guard let panel = panel else { return }
        let screen = chosenScreen()
        let targetFrame = panelFrame(for: screen)
        guard !PanelGeometry.approximatelyEqual(panel.frame, targetFrame) else { return }
        panel.setFrame(targetFrame, display: true)
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        PanelGeometry.panelFrame(
            panelSize: panelSize(for: screen),
            screenFrame: screen.frame,
            allowHorizontalDrag: SettingsManager.shared.allowHorizontalDrag,
            storedHorizontalOffset: CGFloat(SettingsManager.shared.panelHorizontalOffset)
        )
    }

    private func setupHorizontalDragMonitor() {
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
                    // Only start moving after exceeding threshold
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

    /// Choose which screen to display on based on the persisted screen selection.
    private func chosenScreen() -> NSScreen {
        ScreenSelector.shared.selectedScreen ?? ScreenDetector.preferredScreen
    }

    /// Update panel visibility based on settings
    private func updateVisibility() {
        guard let panel = panel else { return }
        syncAutomaticActivationMode()
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

    private func syncAutomaticActivationMode() {
        guard let panel = panel as? KeyablePanel else { return }
        // Automatic panel refreshes should stay passive whenever SuperIsland is
        // not the active app. This preserves input focus in the foreground app.
        panel.allowsInteractiveActivation = Self.automaticPresentationActivationMode(
            appIsActive: NSApp.isActive
        )
    }

    private func shouldShowPanel(on screen: NSScreen) -> Bool {
        Self.resolvedPresentationMode(
            displayMode: SettingsManager.shared.displayMode,
            hasPhysicalNotch: ScreenDetector.screenHasNotch(screen),
            screenCount: max(ScreenSelector.shared.availableScreens.count, 1)
        ) != .menuBar
    }

    nonisolated static func resolvedPresentationMode(
        displayMode: DisplayMode,
        hasPhysicalNotch: Bool,
        screenCount: Int
    ) -> DisplayMode {
        DisplayModeCoordinator.resolveMode(
            displayMode,
            hasPhysicalNotch: hasPhysicalNotch,
            screenCount: screenCount
        )
    }

    private(set) var isFullscreenEdgeRevealActive = false

    private func isActiveSpaceFullscreen() -> Bool {
        let screen = chosenScreen()
        return FullscreenAppDetector.isFullscreenAppActive(screenFrame: screen.frame)
    }

    /// Check if mouse is in the fullscreen reveal zone (top edge when panel is hidden)
    func isMouseInFullscreenRevealZone(
        panelWidth: CGFloat,
        notchWidth: CGFloat,
        hasNotch: Bool
    ) -> Bool {
        guard !hasNotch,
              SettingsManager.shared.hideInFullscreen,
              isFullscreenEdgeRevealActive else { return false }

        let settings = SettingsManager.shared
        let zoneHeight = settings.fullscreenRevealZoneHeight
        let horizontalInset = settings.fullscreenRevealZoneHorizontalInset

        let screen = chosenScreen()
        let mouse = NSEvent.mouseLocation

        // Reveal zone is a wide strip at the top center of the screen
        let zoneWidth = panelWidth + (horizontalInset * 2)
        let zoneRect = CGRect(
            x: screen.frame.midX - zoneWidth / 2,
            y: screen.frame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )

        return zoneRect.contains(mouse)
    }

    /// Update fullscreen edge reveal state based on current conditions
    func updateFullscreenEdgeRevealState() {
        let shouldUseEdgeReveal = SettingsManager.shared.hideInFullscreen
            && !ScreenDetector.screenHasNotch(chosenScreen())
            && isActiveSpaceFullscreen()

        guard shouldUseEdgeReveal != isFullscreenEdgeRevealActive else { return }
        isFullscreenEdgeRevealActive = shouldUseEdgeReveal

        // If entering edge reveal mode and panel is open, close it
        if shouldUseEdgeReveal, appState.surface.isExpanded {
            withAnimation(NotchAnimation.close) {
                appState.surface = .collapsed
            }
        }
    }

    /// Fast check: is the terminal running the active session the foreground app?
    /// Main-thread safe — no AppleScript or subprocess calls.
    func isActiveTerminalForeground() -> Bool {
        guard let sessionId = appState.activeSessionId,
              let session = appState.sessions[sessionId],
              session.termApp != nil else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    func isMouseInsideCollapsedNotchDeadZone(
        panelWidth: CGFloat,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        hasNotch: Bool,
        ignoresHover: Bool
    ) -> Bool {
        guard let panel,
              hasNotch,
              ignoresHover,
              notchWidth > 0,
              notchHeight > 0,
              panelWidth > notchWidth else { return false }

        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let notchMinX = frame.minX + (panelWidth - notchWidth) / 2
        let notchMinY = frame.maxY - notchHeight
        let notchRect = NSRect(
            x: notchMinX,
            y: notchMinY,
            width: notchWidth,
            height: notchHeight
        )
        return notchRect.contains(mouse)
    }

    func isMouseInsidePanelFrame() -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    func windowDidMove(_ notification: Notification) {
        // Drag is handled by setupHorizontalDragMonitor — no correction needed here.
    }

    deinit {
        let environmentMonitor = self.environmentMonitor
        Task { @MainActor in
            environmentMonitor.stopObserving()
        }
        Self.replaceMonitor(currentMonitor: &globalClickMonitor, newMonitor: nil, removeMonitor: NSEvent.removeMonitor)
        Self.replaceMonitor(currentMonitor: &localDragMonitor, newMonitor: nil, removeMonitor: NSEvent.removeMonitor)
    }
}

extension Notification.Name {
    static let superIslandPanelStateDidChange = Notification.Name("SuperIslandPanelStateDidChange")
}
