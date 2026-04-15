import AppKit
import Carbon.HIToolbox
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.superisland", category: "AppDelegate")

    var panelController: PanelWindowController? { displayModeCoordinator?.panelController }
    private var hookServer: HookServer?
    private var hookRecoveryTimer: Timer?
    private var lastHookCheck: Date = .distantPast
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    private var displayModeCoordinator: DisplayModeCoordinator?

    let appState = AppState()

    @objc private func handleIncomingURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        handleIncomingURL(url)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("SuperIsland must stay running")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Pre-set app icon so Dock/menu bar use the packaged bundle icon.
        NSApp.applicationIconImage = SettingsWindowController.bundleAppIcon()
        SettingsWindowController.shared.bind(appState: appState)
        StatusItemController.shared.bind(appState: appState)
        // Start HookServer BEFORE installing hooks into CLI configs.
        // If we write settings.json first, Claude Code picks up the new hooks
        // immediately but the socket isn't listening yet — PermissionRequest
        // hooks get no response and Claude Code denies them.
        hookServer = HookServer(appState: appState)
        hookServer?.start()

        let displayModeCoordinator = DisplayModeCoordinator(appState: appState)
        displayModeCoordinator.start()
        self.displayModeCoordinator = displayModeCoordinator
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleIncomingURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        bootstrapBackgroundServices()

        // Hooks auto-recovery: periodic + app activation trigger
        hookRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }

        #if DEBUG
        // Preview mode: inject mock data if --preview flag is present
        if let scenario = DebugHarness.requestedScenario() {
            Self.log.debug("Loading scenario: \(scenario.rawValue)")
            DebugHarness.apply(scenario, to: appState)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if appState.surface == .collapsed {
                    appState.openSessionList(reason: .boot, animation: NotchAnimation.pop)
                }
            }
            return
        }
        #endif

        // Check for updates silently after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            UpdateChecker.shared.checkForUpdates(silent: true)
        }

        SoundManager.shared.playBoot()
        setupGlobalShortcut()
        observeSettingsChanges()

    }

    private func bootstrapBackgroundServices() {
        Task.detached(priority: .utility) { [weak self] in
            let hooksInstalled = ConfigInstaller.install()
            let usageMonitorManager = UsageMonitorLaunchAgentManager()
            let codexAutoSwitchManager = CodexAutoSwitchLaunchAgentManager()

            let usageMonitorResult: Result<Bool, Error>
            do {
                usageMonitorResult = .success(try usageMonitorManager.repairIfNeeded())
            } catch {
                usageMonitorResult = .failure(error)
            }

            let codexAutoSwitchResult: Result<Bool, Error>
            do {
                codexAutoSwitchResult = .success(try codexAutoSwitchManager.repairIfNeeded())
            } catch {
                codexAutoSwitchResult = .failure(error)
            }

            await MainActor.run { [weak self, hooksInstalled, usageMonitorResult, codexAutoSwitchResult] in
                guard let self else { return }

                if hooksInstalled {
                    Self.log.info("Hooks installed")
                } else {
                    Self.log.warning("Failed to install hooks")
                }

                switch usageMonitorResult {
                case .success(true):
                    Self.log.info("Repaired usage monitor launch agent")
                case .failure(let error):
                    Self.log.error("Failed to repair usage monitor: \(error.localizedDescription)")
                case .success(false):
                    break
                }

                switch codexAutoSwitchResult {
                case .success(true):
                    Self.log.info("Repaired Codex auto-switch launch agent")
                case .failure(let error):
                    Self.log.error("Failed to repair Codex auto-switch watcher: \(error.localizedDescription)")
                case .success(false):
                    break
                }

                self.appState.refreshUsageSnapshot()
                self.appState.startSessionDiscovery()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookRecoveryTimer?.invalidate()
        teardownGlobalShortcut()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        displayModeCoordinator?.stop()
        appState.flushPendingTerminalIndexPersist()
        appState.saveSessions(synchronously: true)
        hookServer?.stop()
        appState.stopSessionDiscovery()
        Task.detached {
            await CodexAppServerClient.shared.stop()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "superisland" else { return }

        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        let route = host.isEmpty ? pathComponents.first ?? "" : host
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let sessionId = queryItems.first(where: { $0.name == "sessionId" })?.value
        let cwd = queryItems.first(where: { $0.name == "cwd" })?.value
        let source = queryItems.first(where: { $0.name == "source" })?.value

        switch route {
        case "settings":
            NSApp.activate(ignoringOtherApps: true)
            SettingsWindowController.shared.show()
        case "session":
            // Session deeplinks should behave like tapping a session row: jump to the
            // tracked terminal/editor target instead of only focusing the in-app card.
            if let matchedSessionId = sessionId.flatMap({ appState.sessions[$0] != nil ? $0 : nil })
                ?? appState.matchingSessionId(cwd: cwd, source: source) {
                appState.jumpToSession(matchedSessionId)
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            if appState.focusSession(cwd: cwd, source: source) != nil {
                displayModeCoordinator?.revealPrimaryInterface()
            } else {
                displayModeCoordinator?.revealPrimaryInterface()
                appState.openSessionList(reason: .deeplink)
            }
        default:
            NSApp.activate(ignoringOtherApps: true)
            displayModeCoordinator?.revealPrimaryInterface()
        }
    }

    // MARK: - Global Shortcuts

    func setupGlobalShortcut() {
        teardownGlobalShortcut()

        // Collect all enabled shortcut bindings, skip duplicates (first wins)
        var bindings: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, action: ShortcutAction)] = []
        var seen: Set<String> = []
        for action in ShortcutAction.allCases {
            guard action.isEnabled else { continue }
            let b = action.binding
            let key = "\(b.keyCode)-\(b.modifiers.rawValue)"
            guard seen.insert(key).inserted else { continue }
            bindings.append((b.keyCode, b.modifiers, action))
        }
        guard !bindings.isEmpty else { return }

        let handler: (NSEvent) -> Bool = { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for b in bindings where event.keyCode == b.keyCode && eventMods == b.mods {
                Task { @MainActor in self?.executeShortcut(b.action) }
                return true
            }
            return false
        }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    private func teardownGlobalShortcut() {
        if let m = globalShortcutMonitor { NSEvent.removeMonitor(m) }
        if let m = localShortcutMonitor { NSEvent.removeMonitor(m) }
        globalShortcutMonitor = nil
        localShortcutMonitor = nil
    }

    private func executeShortcut(_ action: ShortcutAction) {
        switch action {
        case .togglePanel:
            displayModeCoordinator?.togglePrimaryInterface()
        case .approve:
            appState.approvePermission()
        case .approveAlways:
            appState.approvePermission(always: true)
        case .deny:
            appState.denyPermission()
        case .skipQuestion:
            appState.skipQuestion()
        case .jumpToTerminal:
            if let id = appState.activeSessionId {
                appState.jumpToSession(id)
            }
        }
    }

    private func checkAndRepairHooks() {
        guard Date().timeIntervalSince(lastHookCheck) > 60 else { return }
        lastHookCheck = Date()
        let repaired = ConfigInstaller.verifyAndRepair()
        if !repaired.isEmpty {
            Self.log.info("Auto-repaired hooks for: \(repaired.joined(separator: ", "))")
        }
    }

    private func observeSettingsChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.setupGlobalShortcut()
            }
        }
    }
}
