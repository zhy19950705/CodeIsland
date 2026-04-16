import AppKit

enum PanelSpaceTransition: Equatable {
    case enterFullscreen
    case updateVisible
    case waitForFullscreenExit
}

@MainActor
final class PanelEnvironmentMonitor {
    private enum FullscreenRecheck {
        static let interval: Duration = .seconds(1)
    }

    private static let pointerActivityEvents: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .scrollWheel
    ]

    struct Handlers {
        let refreshCurrentScreen: (_ forceRebuild: Bool) -> Void
        let refreshAvailableScreens: () -> Void
        let updateFullscreenEdgeRevealState: () -> Void
        let updateVisibility: () -> Void
        let updatePosition: () -> Void
        let updatePositionIfNeeded: () -> Void
        let currentScreenSelectionPreference: () -> String
        let currentNotchWidthOverride: () -> Int
        let currentSelectionMode: () -> ScreenSelectionMode
        let isActiveSpaceFullscreen: () -> Bool
    }

    private var observers: [NSObjectProtocol] = []
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var fullscreenRecheckTask: Task<Void, Never>?
    private var lastScreenSelectionPreference = ""
    private var lastNotchWidthOverride = SettingsDefaults.notchWidthOverride
    private var lastPointerDrivenRefreshAt: Date = .distantPast
    private var handlers: Handlers?

    private(set) var fullscreenLatch = false

    nonisolated static func needsScreenRefresh(
        previousPreferenceSignature: String,
        newPreferenceSignature: String,
        previousNotchWidthOverride: Int,
        newNotchWidthOverride: Int
    ) -> Bool {
        previousPreferenceSignature != newPreferenceSignature
            || previousNotchWidthOverride != newNotchWidthOverride
    }

    nonisolated static func spaceTransition(
        isFullscreen: Bool,
        fullscreenLatch: Bool
    ) -> PanelSpaceTransition {
        if isFullscreen {
            return .enterFullscreen
        }
        if fullscreenLatch {
            return .waitForFullscreenExit
        }
        return .updateVisible
    }

    func startObserving(appState: AppState, handlers: Handlers) {
        stopObserving()
        self.handlers = handlers
        lastScreenSelectionPreference = handlers.currentScreenSelectionPreference()
        lastNotchWidthOverride = handlers.currentNotchWidthOverride()

        let screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlers?.refreshCurrentScreen(true)
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.handlers?.refreshCurrentScreen(true)
            }
        }
        observers.append(screenChangeObserver)

        let spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceChange()
            }
        }
        observers.append(spaceChangeObserver)

        let appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleFrontmostAppChange()
            }
        }
        observers.append(appActivateObserver)

        let panelStateObserver = NotificationCenter.default.addObserver(
            forName: .superIslandPanelStateDidChange,
            object: appState,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Defer window/frame reconciliation one run-loop turn so SwiftUI can
                // finish swapping detail/list content before AppKit resizes the panel.
                DispatchQueue.main.async { [weak self] in
                    self?.handlers?.updateVisibility()
                    // Surface transitions change the intended panel height, so forcing a
                    // full frame sync is safer than relying on approximate equality.
                    self?.handlers?.updatePosition()
                }
            }
        }
        observers.append(panelStateObserver)

        let conversationStateObserver = NotificationCenter.default.addObserver(
            forName: .superIslandConversationStateDidChange,
            object: ChatHistoryManager.shared,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sessionId = note.userInfo?[ChatHistoryManager.sessionIdUserInfoKey] as? String
                guard self.shouldRefreshDetailLayout(for: appState.surface, sessionId: sessionId) else { return }
                // Transcript parsing completes after the surface is already on screen, so only the frame needs reconciling here.
                DispatchQueue.main.async { [weak self] in
                    self?.handlers?.updatePositionIfNeeded()
                }
            }
        }
        observers.append(conversationStateObserver)

        let settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSettingsChange()
            }
        }
        observers.append(settingsObserver)

        configureAutoScreenPolling()
    }

    func stopObserving() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }
        fullscreenRecheckTask?.cancel()
        fullscreenRecheckTask = nil
        fullscreenLatch = false

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        handlers = nil
    }

    /// Ignore transcript updates for background sessions so panel resizing only tracks the currently visible detail surface.
    private func shouldRefreshDetailLayout(for surface: IslandSurface, sessionId: String?) -> Bool {
        guard case .sessionDetail(let activeSessionId) = surface else { return false }
        guard let sessionId else { return true }
        return sessionId == activeSessionId
    }

    private func handleActiveSpaceChange() {
        guard let handlers else { return }
        handlers.refreshCurrentScreen(false)
        handlers.updateFullscreenEdgeRevealState()

        switch Self.spaceTransition(
            isFullscreen: handlers.isActiveSpaceFullscreen(),
            fullscreenLatch: fullscreenLatch
        ) {
        case .enterFullscreen:
            fullscreenLatch = true
            handlers.updateVisibility()
            startFullscreenRecheckTask()
        case .updateVisible:
            stopFullscreenRecheckTask()
            fullscreenLatch = false
            handlers.updateVisibility()
        case .waitForFullscreenExit:
            startFullscreenRecheckTask()
            break
        }
    }

    private func handleFrontmostAppChange() {
        guard let handlers else { return }
        handlers.refreshCurrentScreen(false)
        handlers.updateFullscreenEdgeRevealState()
        if handlers.isActiveSpaceFullscreen() {
            if !fullscreenLatch {
                fullscreenLatch = true
                handlers.updateVisibility()
            }
            startFullscreenRecheckTask()
            return
        }

        if fullscreenLatch {
            stopFullscreenRecheckTask()
            fullscreenLatch = false
        }
        handlers.updateVisibility()
    }

    private func handleSettingsChange() {
        guard let handlers else { return }

        let newPreference = handlers.currentScreenSelectionPreference()
        let newNotchWidthOverride = handlers.currentNotchWidthOverride()
        if Self.needsScreenRefresh(
            previousPreferenceSignature: lastScreenSelectionPreference,
            newPreferenceSignature: newPreference,
            previousNotchWidthOverride: lastNotchWidthOverride,
            newNotchWidthOverride: newNotchWidthOverride
        ) {
            lastScreenSelectionPreference = newPreference
            lastNotchWidthOverride = newNotchWidthOverride
            handlers.refreshAvailableScreens()
            handlers.refreshCurrentScreen(true)
            configureAutoScreenPolling()
        } else {
            handlers.updateVisibility()
            handlers.updatePosition()
        }
    }

    private func configureAutoScreenPolling() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }

        guard let handlers,
              handlers.currentSelectionMode() == .automatic else { return }

        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.pointerActivityEvents) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePointerActivity()
            }
        }

        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.pointerActivityEvents) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handlePointerActivity()
            }
            return event
        }
    }

    private func handlePointerActivity() {
        guard let handlers else { return }

        let now = Date()
        if handlers.currentSelectionMode() == .automatic,
           now.timeIntervalSince(lastPointerDrivenRefreshAt) >= 0.12 {
            lastPointerDrivenRefreshAt = now
            handlers.refreshCurrentScreen(false)
        }

        if fullscreenLatch {
            reconcileFullscreenLatch()
        }
    }

    private func startFullscreenRecheckTask() {
        guard fullscreenRecheckTask == nil else { return }
        fullscreenRecheckTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.fullscreenLatch {
                try? await Task.sleep(for: FullscreenRecheck.interval)
                guard !Task.isCancelled else { return }
                self.reconcileFullscreenLatch()
            }
        }
    }

    private func stopFullscreenRecheckTask() {
        fullscreenRecheckTask?.cancel()
        fullscreenRecheckTask = nil
    }

    private func reconcileFullscreenLatch() {
        guard let handlers else { return }
        handlers.updateFullscreenEdgeRevealState()
        if handlers.isActiveSpaceFullscreen() {
            if !fullscreenLatch {
                fullscreenLatch = true
                handlers.updateVisibility()
            }
            startFullscreenRecheckTask()
            return
        }

        if fullscreenLatch {
            fullscreenLatch = false
            stopFullscreenRecheckTask()
        }
        handlers.updateVisibility()
    }
}
