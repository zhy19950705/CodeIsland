import AppKit
import SwiftUI
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "Panel")

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
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
/// Also guards against NSHostingView constraint-update re-entrancy crash:
/// during updateConstraints(), SwiftUI may invalidate the view graph and
/// call setNeedsUpdateConstraints again, which AppKit forbids.
private class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// When true, the deferred handler is setting super — don't re-defer.
    private var applyingDeferred = false
    /// Coalesce repeated invalidations so view churn can't enqueue unbounded main-queue blocks.
    private var pendingNeedsUpdateConstraints: Bool?
    private var pendingNeedsLayout: Bool?
    private var hasScheduledNeedsUpdateConstraints = false
    private var hasScheduledNeedsLayout = false

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Always defer `needsUpdateConstraints = true` to the next run-loop turn.
    /// During AppKit's display-cycle (constraint-update or layout phases),
    /// calling setNeedsUpdateConstraints synchronously re-enters
    /// `_postWindowNeedsUpdateConstraints` and throws.  Deferring avoids
    /// that entirely; the one-tick delay is imperceptible.
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

    private var autoScreenPoller: Timer?
    private var fullscreenPoller: Timer?
    private var fullscreenLatch = false
    private var settingsObservers: [NSObjectProtocol] = []
    private var globalClickMonitor: Any?
    private var lastChosenScreenSignature = ""
    private var isAnimatingScreenHop = false
    private var lastNotchWidthOverride = SettingsDefaults.notchWidthOverride
    private var dragStartMouseX: CGFloat?
    private var dragStartPanelX: CGFloat?
    private var isDraggingPanel = false
    private var localDragMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func showPanel() {
        if let panel {
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
        updatePosition()
        panel.orderFrontRegardless()

        // Screen change observer
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentScreen(forceRebuild: true)
                // macOS may not have finished updating NSScreen.screens when the notification fires.
                // Rebuild again after a short delay to pick up the final screen configuration.
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.refreshCurrentScreen(forceRebuild: true)
            }
        }

        // Active space change — check fullscreen
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.refreshCurrentScreen()
                if self.isActiveSpaceFullscreen() {
                    self.fullscreenLatch = true
                    self.updateVisibility()
                    self.startFullscreenExitPoller()
                } else if !self.fullscreenLatch {
                    self.updateVisibility()
                }
                // If latch is set but not detected: ignore (poller will handle exit)
            }
        }

        // Frontmost app change
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.refreshCurrentScreen()
                if !self.fullscreenLatch { self.updateVisibility() }
            }
        }

        let panelStateObserver = NotificationCenter.default.addObserver(
            forName: .codeIslandPanelStateDidChange,
            object: appState,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateVisibility()
                self?.updatePositionIfNeeded()
            }
        }
        settingsObservers.append(panelStateObserver)

        // Observe settings changes (display choice, panel height)
        observeSettingsChanges()
        configureAutoScreenPolling()

        // Global click monitor: close panel + repost click when clicking outside
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
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
    }

    func revealPanel() {
        guard let panel else { return }
        updatePosition()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hidePanel() {
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

    private var lastScreenSelectionPreference = ""

    private func observeSettingsChanges() {
        lastScreenSelectionPreference = ScreenSelector.shared.preferenceSignature
        lastNotchWidthOverride = SettingsManager.shared.notchWidthOverride
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newPreference = ScreenSelector.shared.preferenceSignature
                let newNotchWidthOverride = SettingsManager.shared.notchWidthOverride
                if newPreference != self.lastScreenSelectionPreference
                    || newNotchWidthOverride != self.lastNotchWidthOverride {
                    self.lastScreenSelectionPreference = newPreference
                    self.lastNotchWidthOverride = newNotchWidthOverride
                    ScreenSelector.shared.refreshScreens()
                    self.refreshCurrentScreen(forceRebuild: true)
                    self.configureAutoScreenPolling()
                } else {
                    self.updateVisibility()
                    self.updatePosition()
                }
            }
        }
        settingsObservers.append(observer)
    }

    private func configureAutoScreenPolling() {
        autoScreenPoller?.invalidate()
        autoScreenPoller = nil

        guard ScreenSelector.shared.selectionMode == .automatic else { return }

        autoScreenPoller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentScreen()
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
        guard !approximatelyEqual(panel.frame, targetFrame) else { return }
        panel.setFrame(targetFrame, display: true)
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let size = panelSize(for: screen)
        let screenFrame = screen.frame
        let centeredX = centeredX(for: size, screen: screen)
        let dragOffset = SettingsManager.shared.allowHorizontalDrag
            ? CGFloat(SettingsManager.shared.panelHorizontalOffset)
            : 0
        let x = clampedX(centeredX + dragOffset, panelWidth: size.width, on: screen)
        let y = screenFrame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func centeredX(for size: NSSize, screen: NSScreen) -> CGFloat {
        screen.frame.midX - size.width / 2
    }

    private func clampedX(_ desiredX: CGFloat, panelWidth: CGFloat, on screen: NSScreen) -> CGFloat {
        min(max(desiredX, screen.frame.minX), screen.frame.maxX - panelWidth)
    }

    private func approximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.size.width - rhs.size.width) < tolerance
            && abs(lhs.size.height - rhs.size.height) < tolerance
    }

    private func setupHorizontalDragMonitor() {
        let dragThreshold: CGFloat = 5

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
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
                        guard abs(deltaX) > dragThreshold else { return event }
                        self.isDraggingPanel = true
                    }
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    let newX = self.clampedX(startPanelX + deltaX, panelWidth: size.width, on: screen)
                    let fixedY = screen.frame.maxY - size.height
                    panel.setFrameOrigin(NSPoint(x: newX, y: fixedY))
                }
            case .leftMouseUp:
                if self.isDraggingPanel, let panel = self.panel {
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    let offset = panel.frame.origin.x - self.centeredX(for: size, screen: screen)
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
    }

    /// Choose which screen to display on based on the persisted screen selection.
    private func chosenScreen() -> NSScreen {
        ScreenSelector.shared.selectedScreen ?? ScreenDetector.preferredScreen
    }

    /// Poll every 1.5s while in fullscreen; stop when fullscreen ends
    private func startFullscreenExitPoller() {
        fullscreenPoller?.invalidate()
        fullscreenPoller = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                if !self.isActiveSpaceFullscreen() {
                    self.fullscreenLatch = false
                    self.updateVisibility()
                    timer.invalidate()
                    self.fullscreenPoller = nil
                }
            }
        }
    }

    /// Update panel visibility based on settings
    private func updateVisibility() {
        guard let panel = panel else { return }
        guard shouldShowPanel(on: chosenScreen()) else {
            panel.orderOut(nil)
            return
        }

        let settings = SettingsManager.shared
        if settings.hideInFullscreen && fullscreenLatch {
            panel.orderOut(nil)
            return
        }

        if settings.hideWhenNoSession && appState.activeSessionCount == 0 {
            panel.orderOut(nil)
            return
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
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

    private func isActiveSpaceFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }

        // Detect fullscreen by observing that the menu bar has disappeared on
        // the target screen. macOS fullscreen always hides the menu bar on the
        // host display, so `visibleFrame` becomes equal to `frame`.
        //
        // We deliberately avoid `CGWindowListCopyWindowInfo` here: on macOS
        // 15+ polling that API causes the system to surface spurious "X wants
        // to record your screen" prompts for whichever app is frontmost, and
        // this method runs on a timer.
        let screen = chosenScreen()
        let menuBarGap = screen.frame.maxY - screen.visibleFrame.maxY
        return menuBarGap < 1
    }

    /// Fast check: is the terminal running the active session the foreground app?
    /// Main-thread safe — no AppleScript or subprocess calls.
    func isActiveTerminalForeground() -> Bool {
        guard let sessionId = appState.activeSessionId,
              let session = appState.sessions[sessionId],
              session.termApp != nil else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    func windowDidMove(_ notification: Notification) {
        // Drag is handled by setupHorizontalDragMonitor — no correction needed here.
    }

    deinit {
        autoScreenPoller?.invalidate()
        fullscreenPoller?.invalidate()
        for observer in settingsObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension Notification.Name {
    static let codeIslandPanelStateDidChange = Notification.Name("CodeIslandPanelStateDidChange")
}
