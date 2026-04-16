import AppKit
import SwiftUI
import SuperIslandCore

/// Direct clicks on the island should focus only the panel window, not every app window.
enum PanelDirectClickActivationPolicy: Equatable {
    case panelOnly
}

/// Non-activating panel that can temporarily opt into focus only for explicit user interactions.
final class KeyablePanel: NSPanel {
    /// Keep the panel passive by default so background completion cards do not
    /// steal focus from the app the user is actively typing into.
    var allowsInteractiveActivation = false

    override var canBecomeKey: Bool { allowsInteractiveActivation }
    override var canBecomeMain: Bool { allowsInteractiveActivation }

    /// Bringing every window forward makes panel clicks unexpectedly surface the settings window.
    nonisolated static func directClickActivationPolicy() -> PanelDirectClickActivationPolicy {
        .panelOnly
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            // Transparent areas should behave like they are not there.
            if let contentView,
               contentView.hitTest(event.locationInWindow) == nil {
                repostMouseEvent(event, at: convertPoint(toScreen: event.locationInWindow))
                return
            }
            // A direct click is an explicit user intent to interact with SuperIsland,
            // so it is safe to promote the panel to an active key window here.
            // Only the panel should come forward; otherwise an existing settings
            // window can steal focus and look like the click "opened settings".
            allowsInteractiveActivation = true
            NSApp.activate(ignoringOtherApps: true)
            switch Self.directClickActivationPolicy() {
            case .panelOnly:
                makeKeyAndOrderFront(nil)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func repostMouseEvent(_ event: NSEvent, at screenLocation: NSPoint) {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(screenLocation) }) ?? NSScreen.main
        guard let targetScreen else { return }

        let relativeY = screenLocation.y - targetScreen.frame.minY
        let cgPoint = CGPoint(x: screenLocation.x, y: targetScreen.frame.height - relativeY)

        let mouseType: CGEventType
        switch event.type {
        case .leftMouseDown: mouseType = .leftMouseDown
        case .leftMouseUp: mouseType = .leftMouseUp
        case .rightMouseDown: mouseType = .rightMouseDown
        case .rightMouseUp: mouseType = .rightMouseUp
        case .otherMouseDown: mouseType = .otherMouseDown
        case .otherMouseUp: mouseType = .otherMouseUp
        default: return
        }

        let mouseButton: CGMouseButton = switch event.type {
        case .rightMouseDown, .rightMouseUp:
            .right
        case .otherMouseDown, .otherMouseUp:
            .center
        default:
            .left
        }

        let savedCursorPosition = CGEvent(source: nil)?.location
        if let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: cgPoint,
            mouseButton: mouseButton
        ) {
            cgEvent.post(tap: .cghidEventTap)
        }
        if let savedCursorPosition {
            CGWarpMouseCursorPosition(savedCursorPosition)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }
}

/// Ensures first click on a nonactivating panel still reaches SwiftUI content.
/// It also defers layout invalidation to avoid AppKit/SwiftUI re-entrancy during display updates.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Closed state only needs the top band to accept hits.
    var isExpanded: () -> Bool = { false }
    var collapsedInteractiveHeight: () -> CGFloat = { 44 }

    override func mouseDown(with event: NSEvent) {
        // Only promote the panel when activation has already been allowed by an
        // explicit reveal or a direct click handled at the NSPanel level.
        if let panel = window as? KeyablePanel, panel.allowsInteractiveActivation {
            window?.makeKey()
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isExpanded() {
            return super.hitTest(point)
        }
        let interactiveMinY = bounds.maxY - collapsedInteractiveHeight()
        return point.y >= interactiveMinY ? self : nil
    }
}

/// Old and new frames used by the screen-hop animation.
struct PanelScreenHopFrames {
    let outgoing: NSRect
    let incoming: NSRect
}

/// Motion parameters for screen-hop animation tests and runtime transitions.
struct PanelScreenHopMotion {
    let outgoingOffset: CGFloat
    let incomingOffset: CGFloat
    let fadeOutDuration: TimeInterval
    let incomingPauseDuration: TimeInterval
    let fadeInDuration: TimeInterval
}

@MainActor
class PanelWindowController: NSObject, NSWindowDelegate {
    /// Static animation constants stay here so both runtime code and tests share the same source of truth.
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

    nonisolated static func automaticPresentationActivationMode(appIsActive: Bool) -> Bool {
        // Automatic presentation must stay passive while SuperIsland is in the
        // background, otherwise the completion card can disrupt other apps.
        appIsActive
    }

    var panel: NSPanel?
    var hostingView: NotchHostingView<NotchPanelView>?
    let appState: AppState
    let environmentMonitor = PanelEnvironmentMonitor()
    /// Pointer handling lives outside SwiftUI hover so panel rebuilds do not break interaction state.
    let pointerInteractionController = PanelPointerInteractionController()
    var notchCustomizationObserver: NSObjectProtocol?
    var notchEditingObserver: NSObjectProtocol?
    var liveEditPanel: NotchLiveEditPanel?
    var wasPanelVisibleBeforeLiveEdit = false
    var lastRenderMetrics: NotchRenderMetrics?
    var lastChosenScreenSignature = ""
    var isAnimatingScreenHop = false
    var dragStartMouseX: CGFloat?
    var dragStartPanelX: CGFloat?
    var isDraggingPanel = false
    var localDragMonitor: Any?
    var isFullscreenEdgeRevealActive = false
    var surfaceChangeObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        pointerInteractionController.handleEvent = { [weak self] event in
            self?.handlePointerEvent(event)
        }
        surfaceChangeObserver = NotificationCenter.default.addObserver(
            forName: .superIslandSurfaceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncWindowInteractionBehavior()
            }
        }
        startNotchCustomizationObserversIfNeeded()
    }

    func showPanel() {
        if let panel {
            pointerInteractionController.startObserving()
            syncAutomaticActivationMode()
            syncWindowInteractionBehavior()
            updatePosition()
            updateVisibility()
            panel.orderFrontRegardless()
            reconcilePointerHoverState()
            return
        }

        ScreenSelector.shared.refreshScreens()
        let screen = chosenScreen()
        let contentView = makeHostingView(for: screen)
        self.hostingView = contentView

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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
        installHostingView(contentView, in: panel)
        panel.delegate = self

        self.panel = panel
        self.lastRenderMetrics = renderMetrics(for: screen)
        self.lastChosenScreenSignature = ScreenDetector.signature(for: screen)

        setupHorizontalDragMonitor()
        startNotchCustomizationObserversIfNeeded()
        syncAutomaticActivationMode()
        syncWindowInteractionBehavior()
        updatePosition()
        panel.orderFrontRegardless()
        reconcilePointerHoverState()

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
        pointerInteractionController.startObserving()
        reconcilePointerHoverState()
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

    deinit {
        let environmentMonitor = self.environmentMonitor
        let pointerInteractionController = self.pointerInteractionController
        Task { @MainActor in
            environmentMonitor.stopObserving()
            pointerInteractionController.stopObserving()
        }
        if let notchCustomizationObserver {
            NotificationCenter.default.removeObserver(notchCustomizationObserver)
        }
        if let notchEditingObserver {
            NotificationCenter.default.removeObserver(notchEditingObserver)
        }
        if let surfaceChangeObserver {
            NotificationCenter.default.removeObserver(surfaceChangeObserver)
        }
        Self.replaceMonitor(currentMonitor: &localDragMonitor, newMonitor: nil, removeMonitor: NSEvent.removeMonitor)
    }
}
