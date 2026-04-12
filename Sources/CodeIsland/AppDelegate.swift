import AppKit
import Carbon.HIToolbox
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.codeisland", category: "AppDelegate")

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

        if ConfigInstaller.install() {
            Self.log.info("Hooks installed")
        } else {
            Self.log.warning("Failed to install hooks")
        }

        let displayModeCoordinator = DisplayModeCoordinator(appState: appState)
        displayModeCoordinator.start()
        self.displayModeCoordinator = displayModeCoordinator
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleIncomingURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        let usageMonitorManager = UsageMonitorLaunchAgentManager()
        do {
            if try usageMonitorManager.repairIfNeeded() {
                Self.log.info("Repaired usage monitor launch agent")
            }
        } catch {
            Self.log.error("Failed to repair usage monitor: \(error.localizedDescription)")
        }

        let codexAutoSwitchManager = CodexAutoSwitchLaunchAgentManager()
        do {
            if try codexAutoSwitchManager.repairIfNeeded() {
                Self.log.info("Repaired Codex auto-switch launch agent")
            }
        } catch {
            Self.log.error("Failed to repair Codex auto-switch watcher: \(error.localizedDescription)")
        }
        appState.refreshUsageSnapshot()

        appState.startSessionDiscovery()

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
                    withAnimation(NotchAnimation.pop) {
                        appState.surface = .sessionList
                    }
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

        NSApp.activate(ignoringOtherApps: true)

        switch route {
        case "settings":
            SettingsWindowController.shared.show()
        case "session":
            if let sessionId, appState.focusSession(sessionId: sessionId) {
                displayModeCoordinator?.revealPrimaryInterface()
                return
            }
            if appState.focusSession(cwd: cwd, source: source) != nil {
                displayModeCoordinator?.revealPrimaryInterface()
            } else {
                displayModeCoordinator?.revealPrimaryInterface()
                withAnimation(NotchAnimation.open) {
                    appState.surface = .sessionList
                }
            }
        default:
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
