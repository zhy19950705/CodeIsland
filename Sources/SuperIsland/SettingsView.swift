import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case ai
    case skills
    case behavior
    case appearance
    case mascots
    case sound
    case shortcuts
    case testing
    case hooks
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .ai: return "sparkles"
        case .skills: return "shippingbox.fill"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "paintbrush.fill"
        case .mascots: return "person.2.fill"
        case .sound: return "speaker.wave.2.fill"
        case .shortcuts: return "command.circle.fill"
        case .testing: return "testtube.2"
        case .hooks: return "link.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .ai: return .mint
        case .skills: return .teal
        case .behavior: return .orange
        case .appearance: return .blue
        case .mascots: return .pink
        case .sound: return .green
        case .shortcuts: return .indigo
        case .testing: return .orange
        case .hooks: return .purple
        case .about: return .cyan
        }
    }
}

private struct SidebarGroup: Hashable {
    let title: String?
    let pages: [SettingsPage]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: nil, pages: [.general, .ai, .skills, .behavior, .appearance, .mascots, .sound, .shortcuts]),
    SidebarGroup(title: "SuperIsland", pages: [.testing, .hooks, .about]),
]

// MARK: - Main View

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    let appState: AppState?
    @State private var selectedPage: SettingsPage = .general

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.pages) { page in
                            NavigationLink(value: page) {
                                SidebarRow(page: page)
                            }
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 240)

        } detail: {
            ZStack(alignment: .topLeading) {
                switch selectedPage {
                case .general: GeneralPage()
                case .ai: AIPage()
                case .skills: SkillsPage()
                case .behavior: BehaviorPage()
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .shortcuts: ShortcutsPage()
                case .testing: TestingPage(appState: appState)
                case .hooks: HooksPage(appState: appState)
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum SettingsTestingScenario: String, CaseIterable, Identifiable {
    case working
    case approval
    case question
    case completion
    case multi
    case busy
    case allcli

    var id: String { rawValue }

    var previewScenario: PreviewScenario {
        switch self {
        case .working: return .working
        case .approval: return .approval
        case .question: return .question
        case .completion: return .completion
        case .multi: return .multi
        case .busy: return .busy
        case .allcli: return .allcli
        }
    }

    var titleKey: String { "testing_scenario_\(rawValue)" }
    var detailKey: String { "testing_scenario_\(rawValue)_desc" }
}

private struct PageHeader: View {
    let title: String
    var body: some View {
        EmptyView()
    }
}

private struct SidebarRow: View {
    @ObservedObject private var l10n = L10n.shared
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text(l10n[page.rawValue])
                .font(.system(size: 13))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - General Page

private struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var screenSelector = ScreenSelector.shared
    @AppStorage(SettingsKey.allowHorizontalDrag) private var allowHorizontalDrag = SettingsDefaults.allowHorizontalDrag
    @AppStorage(SettingsKey.menuBarShowDetail) private var menuBarShowDetail = SettingsDefaults.menuBarShowDetail
    @State private var launchAtLogin: Bool
    @State private var displayMode: DisplayMode

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
        _displayMode = State(initialValue: SettingsManager.shared.displayMode)
    }

    var body: some View {
        Form {
            Section {
                Picker(l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Toggle(l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
                Toggle(l10n["allow_horizontal_drag"], isOn: $allowHorizontalDrag)
                    .onChange(of: allowHorizontalDrag) { _, enabled in
                        if !enabled {
                            SettingsManager.shared.panelHorizontalOffset = 0
                        }
                    }
                Text(l10n["allow_horizontal_drag_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(l10n["display_mode"], selection: $displayMode) {
                    Text(l10n["display_mode_auto"]).tag(DisplayMode.auto)
                    Text(l10n["display_mode_notch"]).tag(DisplayMode.notch)
                    Text(l10n["display_mode_menu_bar"]).tag(DisplayMode.menuBar)
                }
                .pickerStyle(.segmented)
                .onChange(of: displayMode) { _, newValue in
                    SettingsManager.shared.displayMode = newValue
                }
                if resolvedDisplayMode == .menuBar {
                    Toggle(l10n["menu_bar_show_detail"], isOn: $menuBarShowDetail)
                    Text(menuBarShortcutHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(l10n["display"], selection: displaySelection) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(screenSelector.availableScreens.enumerated()), id: \.offset) { index, screen in
                        Text(displayLabel(for: screen)).tag(screenOptionID(for: screen, index: index))
                    }
                }
            }

        }
        .formStyle(.grouped)
        .onAppear {
            screenSelector.refreshScreens()
        }
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: {
                switch screenSelector.selectionMode {
                case .automatic:
                    return "auto"
                case .specificScreen:
                    guard let selectedScreen = screenSelector.selectedScreen,
                          let match = Array(screenSelector.availableScreens.enumerated()).first(where: {
                              screenSelector.isSelected($0.element)
                          }) else {
                        return "auto"
                    }
                    return screenOptionID(for: selectedScreen, index: match.offset)
                }
            },
            set: { selection in
                if selection == "auto" {
                    screenSelector.selectAutomatic()
                    return
                }

                guard let match = Array(screenSelector.availableScreens.enumerated()).first(where: {
                    screenOptionID(for: $0.element, index: $0.offset) == selection
                }) else {
                    screenSelector.selectAutomatic()
                    return
                }

                screenSelector.selectScreen(match.element)
            }
        )
    }

    private var resolvedDisplayMode: DisplayMode {
        let screen = screenSelector.selectedScreen ?? ScreenDetector.preferredScreen
        return DisplayModeCoordinator.resolveMode(
            displayMode,
            hasPhysicalNotch: ScreenDetector.screenHasNotch(screen),
            screenCount: max(screenSelector.availableScreens.count, 1)
        )
    }

    private var menuBarShortcutHint: String {
        let shortcut = ShortcutAction.togglePanel.defaultBinding?.displayString ?? "⌘⇧I"
        return "\(l10n["menu_bar_shortcut_hint_prefix"]) \(shortcut). \(l10n["menu_bar_shortcut_hint_suffix"])"
    }

    private func displayLabel(for screen: NSScreen) -> String {
        let baseLabel = screen.isBuiltinDisplay ? l10n["builtin_display"] : screen.localizedName
        var suffixes: [String] = []

        if screen == NSScreen.main {
            suffixes.append(l10n["main_display"])
        }
        if ScreenDetector.screenHasNotch(screen) {
            suffixes.append(l10n["notch"])
        }

        guard !suffixes.isEmpty else { return baseLabel }
        return ([baseLabel] + suffixes).joined(separator: " ")
    }

    private func screenOptionID(for screen: NSScreen, index: Int) -> String {
        if let displayID = screen.displayID {
            return "screen-\(displayID)"
        }
        return "screen-\(screen.localizedName)-\(index)"
    }
}

// MARK: - AI Page

private struct AIPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var usageSnapshot: UsageSnapshot = UsageSnapshotStore.load()
    @State private var usageMonitorSnapshot = Self.loadingUsageMonitorSnapshot
    @State private var usageStatusMessage = ""
    @State private var usageStatusIsError = false
    @State private var isTogglingUsageMonitor = false
    @State private var isRefreshingUsage = false
    @State private var codexStatus: CodexAccountManagerStatus?
    @State private var codexAccounts: [CodexManagedAccount] = []
    @State private var codexStatusMessage = ""
    @State private var codexStatusIsError = false
    @State private var isTogglingAutoSwitch = false
    @State private var isRunningAutoSwitch = false
    @State private var autoSwitchSnapshot = Self.loadingAutoSwitchSnapshot
    @State private var autoSwitch5hThreshold = 10
    @State private var autoSwitchWeeklyThreshold = 5
    @State private var autoSwitchAPIUsageEnabled = true

    private let usageMonitorManager = UsageMonitorLaunchAgentManager()
    private let codexAccountManager = CodexAccountManager()
    private let autoSwitchManager = CodexAutoSwitchLaunchAgentManager()

    private static let loadingUsageMonitorSnapshot = UsageMonitorLaunchAgentSnapshot(
        state: .disabled,
        detail: "Loading...",
        plistPath: ""
    )

    private static let loadingAutoSwitchSnapshot = CodexAutoSwitchLaunchAgentSnapshot(
        state: .disabled,
        detail: "Loading...",
        plistPath: ""
    )

    var body: some View {
        Form {
            Section(l10n["usage_monitor_section"]) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n["usage_monitor"])
                    Text(usageMonitorSnapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await toggleUsageMonitor() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTogglingUsageMonitor {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(usageMonitorSnapshot.state == .enabled ? l10n["disable_usage_monitor"] : l10n["enable_usage_monitor"])
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(usageMonitorSnapshot.state == .unavailable || isTogglingUsageMonitor || isRefreshingUsage)

                    Button {
                        Task { await runUsageRefresh() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRefreshingUsage {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(l10n["refresh_now"])
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(usageMonitorSnapshot.state == .unavailable || isRefreshingUsage || isTogglingUsageMonitor)
                }

                if !usageStatusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: usageStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(usageStatusIsError ? .red : .green)
                        Text(usageStatusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if usageSnapshot.providers.isEmpty {
                    Text(l10n["usage_snapshot_empty"])
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usageSnapshot.providers) { provider in
                        UsageProviderRow(provider: provider)
                    }
                }
            }

            Section(l10n["codex_accounts_section"]) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n["codex_accounts"])
                    Text(l10n["codex_accounts_desc"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            do {
                                _ = try codexAccountManager.syncCurrentAuth()
                                await refreshCodexAccounts()
                                codexStatusMessage = l10n["codex_account_sync_complete"]
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    } label: {
                        Text(l10n["codex_account_sync_current"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        guard let selectedURL = chooseCodexImportPath() else { return }
                        Task {
                            do {
                                let summary = try codexAccountManager.importPath(selectedURL)
                                await refreshCodexAccounts()
                                codexStatusMessage = importSummary(summary)
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    } label: {
                        Text(l10n["codex_account_import"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button {
                        do {
                            try codexAccountManager.launchCodexLoginInTerminal()
                            codexStatusMessage = l10n["codex_account_login_started"]
                            codexStatusIsError = false
                        } catch {
                            codexStatusMessage = error.localizedDescription
                            codexStatusIsError = true
                        }
                    } label: {
                        Text(l10n["codex_account_login"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        do {
                            try codexAccountManager.launchCodexLoginInTerminal(deviceAuth: true)
                            codexStatusMessage = l10n["codex_account_login_device_started"]
                            codexStatusIsError = false
                        } catch {
                            codexStatusMessage = error.localizedDescription
                            codexStatusIsError = true
                        }
                    } label: {
                        Text(l10n["codex_account_login_device_auth"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let active = codexStatus?.activeAccount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(l10n["codex_account_active_label"]): \(active.displayName)")
                        Text(active.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let currentAuth = codexStatus?.currentAuth,
                          let email = currentAuth.email {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(l10n["codex_account_current_auth"]): \(email)")
                        if let plan = currentAuth.planType {
                            Text(plan.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !codexStatusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: codexStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(codexStatusIsError ? .red : .green)
                        Text(codexStatusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if codexAccounts.isEmpty {
                    Text(l10n["codex_accounts_empty"])
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(codexAccounts) { account in
                        CodexManagedAccountRow(
                            account: account,
                            isActive: account.accountKey == codexStatus?.registry.activeAccountKey,
                            onActivate: {
                                Task {
                                    do {
                                        _ = try codexAccountManager.activateAccount(account.accountKey)
                                        await refreshCodexAccounts()
                                        codexStatusMessage = l10n["codex_account_activate_complete"]
                                        codexStatusIsError = false
                                    } catch {
                                        codexStatusMessage = error.localizedDescription
                                        codexStatusIsError = true
                                    }
                                }
                            },
                            onRemove: {
                                Task {
                                    do {
                                        _ = try codexAccountManager.removeAccounts(accountKey: account.accountKey)
                                        await refreshCodexAccounts()
                                        codexStatusMessage = l10n["codex_account_remove_complete"]
                                        codexStatusIsError = false
                                    } catch {
                                        codexStatusMessage = error.localizedDescription
                                        codexStatusIsError = true
                                    }
                                }
                            }
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n["codex_auto_switch"])
                    Text(autoSwitchSnapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await toggleAutoSwitch() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTogglingAutoSwitch {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(autoSwitchSnapshot.state == .enabled ? l10n["codex_auto_switch_disable"] : l10n["codex_auto_switch_enable"])
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(autoSwitchSnapshot.state == .unavailable || isTogglingAutoSwitch || isRunningAutoSwitch)

                    Button {
                        Task { await runAutoSwitchNow() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRunningAutoSwitch {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(l10n["codex_auto_switch_run_now"])
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(autoSwitchSnapshot.state == .unavailable || isRunningAutoSwitch || isTogglingAutoSwitch)
                }

                Stepper(value: Binding(
                    get: { autoSwitch5hThreshold },
                    set: { newValue in
                        autoSwitch5hThreshold = newValue
                        updateAutoSwitchThresholds(fiveHour: newValue, weekly: nil)
                    }
                ), in: 0...100, step: 1) {
                    Text("\(l10n["codex_auto_switch_threshold_5h"]) \(autoSwitch5hThreshold)%")
                }

                Stepper(value: Binding(
                    get: { autoSwitchWeeklyThreshold },
                    set: { newValue in
                        autoSwitchWeeklyThreshold = newValue
                        updateAutoSwitchThresholds(fiveHour: nil, weekly: newValue)
                    }
                ), in: 0...100, step: 1) {
                    Text("\(l10n["codex_auto_switch_threshold_weekly"]) \(autoSwitchWeeklyThreshold)%")
                }

                Toggle(l10n["codex_auto_switch_api_usage"], isOn: Binding(
                    get: { autoSwitchAPIUsageEnabled },
                    set: { newValue in
                        autoSwitchAPIUsageEnabled = newValue
                        updateAutoSwitchAPIUsage(newValue)
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                await refreshUsage()
                await refreshCodexAccounts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UsageSnapshotStore.didUpdateNotification)) { _ in
            Task { await refreshUsage() }
        }
    }

    @MainActor
    private func refreshUsage() async {
        let payload = await Task.detached(priority: .userInitiated) {
            let usageSnapshot = UsageSnapshotStore.load()
            let monitorSnapshot = UsageMonitorLaunchAgentManager().snapshot()

            return (
                usageSnapshot,
                monitorSnapshot
            )
        }.value
        usageSnapshot = payload.0
        usageMonitorSnapshot = payload.1
    }

    @MainActor
    private func refreshCodexAccounts() async {
        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                let accountManager = CodexAccountManager()
                let status = try accountManager.status()
                let accounts = try accountManager.listAccounts(syncCurrentAuth: false)
                let autoSwitchSnapshot = CodexAutoSwitchLaunchAgentManager().snapshot()

                return (
                    status,
                    accounts,
                    autoSwitchSnapshot
                )
            }.value
            codexStatus = payload.0
            codexAccounts = payload.1
            autoSwitchSnapshot = payload.2
            autoSwitch5hThreshold = payload.0.registry.autoSwitch.threshold5hPercent
            autoSwitchWeeklyThreshold = payload.0.registry.autoSwitch.thresholdWeeklyPercent
            autoSwitchAPIUsageEnabled = payload.0.registry.api.usage
        } catch {
            let fallbackSnapshot = await Task.detached(priority: .userInitiated) {
                CodexAutoSwitchLaunchAgentManager().snapshot()
            }.value
            codexStatus = nil
            codexAccounts = []
            autoSwitchSnapshot = fallbackSnapshot
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
        }
    }

    @MainActor
    private func toggleUsageMonitor() async {
        isTogglingUsageMonitor = true
        defer { isTogglingUsageMonitor = false }

        do {
            let shouldEnable = usageMonitorSnapshot.state != .enabled
            try await Task.detached(priority: .userInitiated) {
                try UsageMonitorLaunchAgentManager().setEnabled(shouldEnable)
            }.value
            await refreshUsage()
            usageStatusMessage = shouldEnable
                ? l10n["usage_monitor_enabled"]
                : l10n["usage_monitor_disabled"]
            usageStatusIsError = false
        } catch {
            usageStatusMessage = error.localizedDescription
            usageStatusIsError = true
            await refreshUsage()
        }
    }

    @MainActor
    private func runUsageRefresh() async {
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            try await usageMonitorManager.runNow()
            await refreshUsage()
            usageStatusMessage = l10n["usage_refresh_complete"]
            usageStatusIsError = false
        } catch {
            usageStatusMessage = error.localizedDescription
            usageStatusIsError = true
        }
    }

    @MainActor
    private func toggleAutoSwitch() async {
        isTogglingAutoSwitch = true
        defer { isTogglingAutoSwitch = false }

        do {
            let shouldEnable = autoSwitchSnapshot.state != .enabled
            try await Task.detached(priority: .userInitiated) {
                let accountManager = CodexAccountManager()
                let autoSwitchManager = CodexAutoSwitchLaunchAgentManager()
                _ = try accountManager.updateConfiguration(autoSwitchEnabled: shouldEnable)
                try autoSwitchManager.setEnabled(shouldEnable)
            }.value
            await refreshCodexAccounts()
            codexStatusMessage = shouldEnable
                ? l10n["codex_auto_switch_enabled"]
                : l10n["codex_auto_switch_disabled"]
            codexStatusIsError = false
        } catch {
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
            await refreshCodexAccounts()
        }
    }

    @MainActor
    private func runAutoSwitchNow() async {
        isRunningAutoSwitch = true
        defer { isRunningAutoSwitch = false }

        do {
            try await autoSwitchManager.runNow()
            await refreshCodexAccounts()
            codexStatusMessage = l10n["codex_auto_switch_run_complete"]
            codexStatusIsError = false
        } catch {
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
        }
    }

    private func updateAutoSwitchThresholds(fiveHour: Int?, weekly: Int?) {
        Task {
            do {
                _ = try codexAccountManager.updateConfiguration(
                    threshold5hPercent: fiveHour,
                    thresholdWeeklyPercent: weekly
                )
                await refreshCodexAccounts()
            } catch {
                codexStatusMessage = error.localizedDescription
                codexStatusIsError = true
            }
        }
    }

    private func chooseCodexImportPath() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func importSummary(_ summary: CodexImportSummary) -> String {
        "\(summary.importedCount) \(l10n["codex_account_imported"]) · \(summary.updatedCount) \(l10n["codex_account_updated"]) · \(summary.skippedCount) \(l10n["codex_account_skipped"])"
    }

    private func updateAutoSwitchAPIUsage(_ enabled: Bool) {
        Task {
            do {
                _ = try codexAccountManager.updateConfiguration(apiUsageEnabled: enabled)
                await refreshCodexAccounts()
            } catch {
                codexStatusMessage = error.localizedDescription
                codexStatusIsError = true
            }
        }
    }
}

// MARK: - Behavior Page

private struct BehaviorPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.hideInFullscreen) private var hideInFullscreen = SettingsDefaults.hideInFullscreen
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
    @AppStorage(SettingsKey.completionCardDisplaySeconds) private var completionCardDisplaySeconds = SettingsDefaults.completionCardDisplaySeconds
    @AppStorage(SettingsKey.sessionTimeout) private var sessionTimeout = SettingsDefaults.sessionTimeout
    @AppStorage(SettingsKey.maxToolHistory) private var maxToolHistory = SettingsDefaults.maxToolHistory

    var body: some View {
        Form {
            Section(l10n["display_section"]) {
                BehaviorToggleRow(
                    title: l10n["hide_in_fullscreen"],
                    desc: l10n["hide_in_fullscreen_desc"],
                    isOn: $hideInFullscreen,
                    animation: .hideFullscreen
                )
                BehaviorToggleRow(
                    title: l10n["hide_when_no_session"],
                    desc: l10n["hide_when_no_session_desc"],
                    isOn: $hideWhenNoSession,
                    animation: .hideNoSession
                )
                BehaviorToggleRow(
                    title: l10n["smart_suppress"],
                    desc: l10n["smart_suppress_desc"],
                    isOn: $smartSuppress,
                    animation: .smartSuppress
                )
                BehaviorToggleRow(
                    title: l10n["collapse_on_mouse_leave"],
                    desc: l10n["collapse_on_mouse_leave_desc"],
                    isOn: $collapseOnMouseLeave,
                    animation: .collapseMouseLeave
                )
                Picker(selection: $completionCardDisplaySeconds) {
                    Text("5s").tag(5)
                    Text("8s").tag(8)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("20s").tag(20)
                } label: {
                    Text(l10n["completion_card_display_time"])
                    Text(l10n["completion_card_display_time_desc"])
                }
            }

            Section(l10n["sessions"]) {
                Picker(selection: $sessionTimeout) {
                    Text(l10n["no_cleanup"]).tag(0)
                    Text(l10n["10_minutes"]).tag(10)
                    Text(l10n["30_minutes"]).tag(30)
                    Text(l10n["1_hour"]).tag(60)
                    Text(l10n["2_hours"]).tag(120)
                    Text(l10n["1_day"]).tag(1440)
                } label: {
                    Text(l10n["session_cleanup"])
                    Text(l10n["session_cleanup_desc"])
                }
                Picker(selection: $maxToolHistory) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                } label: {
                    Text(l10n["tool_history_limit"])
                    Text(l10n["tool_history_limit_desc"])
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Testing Page

private struct TestingPage: View {
    @ObservedObject private var l10n = L10n.shared
    let appState: AppState?

    @State private var selectedScenario: SettingsTestingScenario = .multi
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section(l10n["testing_preview_section"]) {
                Picker(l10n["testing_preview_scenario"], selection: $selectedScenario) {
                    ForEach(SettingsTestingScenario.allCases) { scenario in
                        Text(l10n[scenario.titleKey]).tag(scenario)
                    }
                }

                Text(l10n[selectedScenario.detailKey])
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        appState?.loadTestingScenario(selectedScenario.previewScenario)
                        statusMessage = l10n["testing_preview_loaded"]
                        statusIsError = false
                    } label: {
                        Text(l10n["testing_load_preview"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState == nil)

                    Button(role: .destructive) {
                        appState?.clearTestingScenarios()
                        statusMessage = l10n["testing_preview_cleared"]
                        statusIsError = false
                    } label: {
                        Text(l10n["testing_clear_preview"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState == nil)
                }

                if appState == nil {
                    Text(l10n["testing_unavailable"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(l10n["testing_live_checks"]) {
                Button {
                    do {
                        try SettingsNotificationTester.sendTestNotification()
                        statusMessage = l10n["testing_notification_sent"]
                        statusIsError = false
                    } catch {
                        statusMessage = error.localizedDescription
                        statusIsError = true
                    }
                } label: {
                    Text(l10n["testing_send_notification"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(l10n["testing_send_notification_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n["testing_data_section"]) {
                Button(role: .destructive) {
                    appState?.clearAllSessionRecords()
                    statusMessage = l10n["testing_all_sessions_cleared"]
                    statusIsError = false
                } label: {
                    Text(l10n["testing_clear_all_sessions"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState == nil)

                Text(l10n["testing_clear_all_sessions_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !statusMessage.isEmpty {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hooks Page

private struct HooksPage: View {
    @ObservedObject private var l10n = L10n.shared
    let appState: AppState?
    @State private var cliSnapshots: [CLIIntegrationSnapshot] = []
    @State private var editorSnapshots: [EditorBridgeSnapshot] = []
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = UUID()
    @State private var isExportingDiagnostics = false

    private let cliIntegrationManager = CLIIntegrationManager()
    private let editorBridgeManager = EditorBridgeManager()

    private var enabledHealthyCount: Int {
        cliSnapshots.filter { snapshot in
            ConfigInstaller.isEnabled(source: snapshot.integration.rawValue) && snapshot.state == .active
        }.count
    }

    private var enabledNeedsRepairCount: Int {
        cliSnapshots.filter { snapshot in
            ConfigInstaller.isEnabled(source: snapshot.integration.rawValue) && snapshot.state != .active
        }.count
    }

    private var disabledCount: Int {
        cliSnapshots.filter { snapshot in
            !ConfigInstaller.isEnabled(source: snapshot.integration.rawValue)
        }.count
    }

    var body: some View {
        Form {
            Section(l10n["hooks_health"]) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: enabledNeedsRepairCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(enabledNeedsRepairCount == 0 ? .green : .orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(enabledNeedsRepairCount == 0 ? l10n["hooks_health_ok"] : "\(enabledNeedsRepairCount) \(l10n["hooks_health_attention"])")
                            .font(.headline)
                        Text("\(l10n["hooks_health_enabled_active"]): \(enabledHealthyCount)")
                            .foregroundStyle(.secondary)
                        Text("\(l10n["hooks_health_enabled_issues"]): \(enabledNeedsRepairCount)")
                            .foregroundStyle(enabledNeedsRepairCount == 0 ? Color.secondary : .orange)
                        Text("\(l10n["hooks_health_disabled"]): \(disabledCount)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        let repaired = ConfigInstaller.verifyAndRepair()
                        refreshDiagnostics()
                        if repaired.isEmpty {
                            statusMessage = enabledNeedsRepairCount == 0
                                ? l10n["hooks_repair_not_needed"]
                                : l10n["install_failed"]
                            statusIsError = enabledNeedsRepairCount != 0
                        } else {
                            statusMessage = "\(l10n["hooks_repaired"]): \(repaired.joined(separator: ", "))"
                            statusIsError = false
                        }
                    } label: {
                        Text(l10n["hooks_repair"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        refreshDiagnostics()
                    } label: {
                        Text(l10n["hooks_refresh_status"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section(l10n["editor_bridges"]) {
                ForEach(editorSnapshots) { snapshot in
                    EditorBridgeRow(snapshot: snapshot) {
                        editorBridgeManager.openInstallLocation(for: snapshot.host)
                    } onInstallExtension: {
                        do {
                            try IDEExtensionInstaller.install(snapshot.host.extensionHost)
                            refreshDiagnostics()
                            statusMessage = "\(snapshot.host.title) \(l10n["editor_extension_installed"].lowercased())"
                            statusIsError = false
                        } catch {
                            statusMessage = error.localizedDescription
                            statusIsError = true
                        }
                    } onReinstallExtension: {
                        do {
                            try IDEExtensionInstaller.reinstall(snapshot.host.extensionHost)
                            refreshDiagnostics()
                            statusMessage = "\(snapshot.host.title) \(l10n["reinstall_extension"].lowercased())"
                            statusIsError = false
                        } catch {
                            statusMessage = error.localizedDescription
                            statusIsError = true
                        }
                    } onUninstallExtension: {
                        IDEExtensionInstaller.uninstall(snapshot.host.extensionHost)
                        refreshDiagnostics()
                        statusMessage = "\(snapshot.host.title) \(l10n["uninstall_extension"].lowercased())"
                        statusIsError = false
                    }
                }
            }

            Section(l10n["cli_integrations"]) {
                ForEach(cliSnapshots) { snapshot in
                    CLIIntegrationRow(snapshot: snapshot) {
                        cliIntegrationManager.openConfig(for: snapshot.integration)
                    } onToggle: { enabled in
                        _ = ConfigInstaller.setEnabled(source: snapshot.integration.rawValue, enabled: enabled)
                        refreshDiagnostics()
                    }
                    .id("\(snapshot.integration.rawValue)-\(refreshKey)")
                }
            }

            Section(l10n["management"]) {
                HStack(spacing: 8) {
                    Button {
                        // Enable all detected CLIs before reinstalling
                        for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                        }
                        if ConfigInstaller.cliExists(source: "opencode") {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_opencode")
                        }
                        if ConfigInstaller.install() {
                            refreshDiagnostics()
                            statusMessage = l10n["hooks_installed"]
                            statusIsError = false
                        } else {
                            statusMessage = l10n["install_failed"]
                            statusIsError = true
                        }
                    } label: {
                        Text(l10n["reinstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        // Disable all CLIs before uninstalling
                        for cli in ConfigInstaller.allCLIs {
                            UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                        }
                        UserDefaults.standard.set(false, forKey: "cli_enabled_opencode")
                        ConfigInstaller.uninstall()
                        refreshDiagnostics()
                        statusMessage = l10n["hooks_uninstalled"]
                        statusIsError = false
                    } label: {
                        Text(l10n["uninstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Diagnostics") {
                Button {
                    exportDiagnostics()
                } label: {
                    HStack {
                        Text("Export diagnostics archive")
                        Spacer()
                        if isExportingDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExportingDiagnostics || appState == nil)

                Text("Bundles live session state, hook configs, usage cache, macOS info, and recent SuperIsland logs into a zip archive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDiagnostics() }
    }

    private func refreshDiagnostics() {
        cliSnapshots = cliIntegrationManager.snapshots()
        editorSnapshots = editorBridgeManager.snapshots()
        refreshKey = UUID()
    }

    private func exportDiagnostics() {
        guard let appState else { return }

        let panel = NSSavePanel()
        panel.title = "Export SuperIsland Diagnostics"
        panel.nameFieldStringValue = "SuperIsland-Diagnostics.zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isExportingDiagnostics = true
        statusMessage = ""
        statusIsError = false

        let snapshot = appState.diagnosticsSnapshot()
        Task {
            do {
                let result = try await DiagnosticsExporter.shared.exportArchive(
                    snapshot: snapshot,
                    to: destinationURL
                )
                await MainActor.run {
                    isExportingDiagnostics = false
                    statusIsError = false
                    statusMessage = result.warnings.isEmpty
                        ? "Diagnostics exported to \(result.archiveURL.path)"
                        : "Diagnostics exported with \(result.warnings.count) warning(s): \(result.archiveURL.path)"
                    NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL])
                }
            } catch {
                await MainActor.run {
                    isExportingDiagnostics = false
                    statusIsError = true
                    statusMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct EditorBridgeRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: EditorBridgeSnapshot
    let onOpen: () -> Void
    let onInstallExtension: () -> Void
    let onReinstallExtension: () -> Void
    let onUninstallExtension: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.host.systemName)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.host.title)
                    Text(l10n[snapshot.state.detailKey])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(snapshot.extensionInstalled ? l10n["editor_extension_installed"] : l10n["editor_extension_missing"])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(snapshot.extensionInstalled ? .green : .orange)
                    if let installPath = snapshot.installPath {
                        Text(installPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                IntegrationStateBadge(title: l10n[snapshot.state.titleKey], state: snapshot.state)
                if snapshot.state != .unavailable {
                    Button(l10n["open_app"]) {
                        onOpen()
                    }
                    .buttonStyle(.link)
                }
                if snapshot.extensionInstalled {
                    Button(l10n["reinstall_extension"]) {
                        onReinstallExtension()
                    }
                    .buttonStyle(.link)

                    Button(l10n["uninstall_extension"]) {
                        onUninstallExtension()
                    }
                    .buttonStyle(.link)
                } else if snapshot.state != .unavailable {
                    Button(l10n["install_extension"]) {
                        onInstallExtension()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

private struct CLIIntegrationRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: CLIIntegrationSnapshot
    let onOpenConfig: () -> Void
    let onToggle: (Bool) -> Void

    @State private var enabled: Bool

    init(snapshot: CLIIntegrationSnapshot, onOpenConfig: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.snapshot = snapshot
        self.onOpenConfig = onOpenConfig
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: snapshot.integration.rawValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = cliIcon(source: snapshot.integration.rawValue, size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.integration.title)
                    Text(snapshot.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                IntegrationStateBadge(title: l10n[snapshot.state.titleKey], state: snapshot.state)
                if snapshot.configPath != nil {
                    Button(l10n["open_config"]) {
                        onOpenConfig()
                    }
                    .buttonStyle(.link)
                }
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, newValue in
                        onToggle(newValue)
                    }
            }
        }
    }
}

private struct IntegrationStateBadge: View {
    let title: String
    let state: Any

    private var color: Color {
        switch state {
        case let editor as EditorBridgeState:
            switch editor {
            case .live: return .green
            case .installed: return .blue
            case .unavailable: return .secondary
            }
        case let cli as CLIIntegrationState:
            switch cli {
            case .active: return .green
            case .installed: return .blue
            case .notInstalled: return .orange
            case .cliNotFound: return .secondary
            case .disabled: return .pink
            }
        default:
            return .secondary
        }
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

private struct UsageProviderRow: View {
    @ObservedObject private var l10n = L10n.shared
    let provider: UsageProviderSnapshot
    @State private var selectedHistoryPreset: UsageHistoryRangePreset = .recent30Days

    private var availableHistories: [UsageHistoryRangeSnapshot] {
        (provider.history ?? []).sorted { $0.preset.sortOrder < $1.preset.sortOrder }
    }

    private var selectedHistory: UsageHistoryRangeSnapshot? {
        availableHistories.first(where: { $0.preset == selectedHistoryPreset }) ?? availableHistories.first
    }

    private var selectedHistoryBinding: Binding<UsageHistoryRangePreset> {
        Binding(
            get: {
                availableHistories.contains(where: { $0.preset == selectedHistoryPreset })
                    ? selectedHistoryPreset
                    : (availableHistories.first?.preset ?? .recent30Days)
            },
            set: { selectedHistoryPreset = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.source.title)
                Spacer()
                if let updatedAtUnix = provider.updatedAtUnix {
                    Text(relativeTime(updatedAtUnix))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                usageBadge(title: provider.primary.label, percentage: provider.primary.percentage, detail: provider.primary.detail)
                usageBadge(title: provider.secondary.label, percentage: provider.secondary.percentage, detail: provider.secondary.detail)
            }
            if let summary = provider.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if availableHistories.count > 1 {
                Picker("", selection: selectedHistoryBinding) {
                    ForEach(availableHistories.map(\.preset), id: \.self) { preset in
                        Text(historyTitle(for: preset))
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let selectedHistory {
                Text(historySummary(selectedHistory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                usageHistoryTable(selectedHistory)
                    .padding(.top, 4)
            } else if let monthly = provider.monthly {
                Text(monthlySummary(monthly))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func usageHistoryTable(_ history: UsageHistoryRangeSnapshot) -> some View {
        if history.rows.isEmpty {
            Text(l10n["usage_breakdown_empty"])
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            FrozenUsageHistoryTable(
                rows: displayRows(for: history),
                titles: UsageHistoryHeaderTitles(
                    date: l10n["usage_table_date"],
                    model: l10n["usage_table_model"],
                    input: l10n["usage_table_input"],
                    output: l10n["usage_table_output"],
                    total: l10n["usage_table_total"],
                    cost: l10n["usage_table_cost"]
                ),
                metrics: tableMetrics
            )
            .frame(height: tableHeight(for: history.rows.count))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func usageBadge(title: String, percentage: Int, detail: String) -> some View {
        let isRemaining = provider.source == .codex
        let secondaryLabel = isRemaining ? l10n["usage_remaining"] : l10n["usage_used"]
        let primaryValue = isRemaining ? 100 - percentage : percentage
        let primaryLabel = l10n["usage_used"]

        return VStack(alignment: .leading, spacing: 2) {
            if isRemaining {
                Text("\(title) · \(primaryLabel) \(primaryValue)% / \(secondaryLabel) \(percentage)%")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("\(title) · \(percentage)% \(secondaryLabel)")
                    .font(.system(size: 12, weight: .medium))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeTime(_ unix: TimeInterval) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(timeIntervalSince1970: unix), relativeTo: Date())
    }

    private func historyTitle(for preset: UsageHistoryRangePreset) -> String {
        switch preset {
        case .thisWeek:
            l10n["usage_range_this_week"]
        case .thisMonth:
            l10n["usage_range_this_month"]
        case .recent30Days:
            l10n["usage_range_recent_30_days"]
        }
    }

    private func historySummary(_ history: UsageHistoryRangeSnapshot) -> String {
        let label = history.label ?? inferredHistoryLabel(history)
        let tokens = tokenSummary(history.totalTokens)
        if let costUSD = history.costUSD {
            return "\(historyTitle(for: history.preset)) · \(label) · \(tokens) · \(formatCurrency(costUSD))"
        }
        return "\(historyTitle(for: history.preset)) · \(label) · \(tokens)"
    }

    private func displayRows(for history: UsageHistoryRangeSnapshot) -> [UsageHistoryDisplayRow] {
        history.rows.enumerated().map { index, row in
            UsageHistoryDisplayRow(
                id: row.id,
                date: shortDate(row.dayStartUnix),
                model: row.model,
                input: compactMetric(row.inputTokens),
                output: compactMetric(row.outputTokens),
                total: compactMetric(row.totalTokens),
                cost: row.costUSD.map(formatCurrency) ?? "—",
                striped: index.isMultiple(of: 2)
            )
        }
    }

    private func monthlySummary(_ monthly: UsageMonthlyStat) -> String {
        let tokens = tokenSummary(monthly.totalTokens)
        if let costUSD = monthly.costUSD {
            return "\(l10n["usage_recent_30_days"]) · \(monthly.label) · \(tokens) · \(formatCurrency(costUSD))"
        }
        return "\(l10n["usage_recent_30_days"]) · \(monthly.label) · \(tokens)"
    }

    private func tokenSummary(_ totalTokens: Int) -> String {
        let value = Double(totalTokens)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0

        if value >= 1_000_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0"
            return "\(number)M \(l10n["usage_tokens"])"
        }
        if value >= 1_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000)) ?? "0"
            return "\(number)K \(l10n["usage_tokens"])"
        }
        let number = formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
        return "\(number) \(l10n["usage_tokens"])"
    }

    private func compactMetric(_ totalTokens: Int) -> String {
        let value = Double(totalTokens)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0

        if value >= 1_000_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0"
            return "\(number)M"
        }
        if value >= 1_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000)) ?? "0"
            return "\(number)K"
        }
        return formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
    }

    private func shortDate(_ unix: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: unix))
    }

    private var tableMetrics: UsageHistoryTableMetrics {
        UsageHistoryTableMetrics(
            dateWidth: historyDateColumnWidth,
            modelWidth: historyModelColumnWidth,
            metricWidth: historyMetricColumnWidth,
            costWidth: historyCostColumnWidth
        )
    }

    private var historyDateColumnWidth: CGFloat { 80 }
    private var historyModelColumnWidth: CGFloat { 70 }
    private var historyMetricColumnWidth: CGFloat { 80 }
    private var historyCostColumnWidth: CGFloat { 80 }

    private func inferredHistoryLabel(_ history: UsageHistoryRangeSnapshot) -> String {
        guard let first = history.rows.first?.dayStartUnix,
              let last = history.rows.last?.dayStartUnix else {
            return ""
        }
        return "\(shortDate(last)) - \(shortDate(first))"
    }

    private func tableHeight(for rowCount: Int) -> CGFloat {
        min(max(CGFloat(rowCount) * tableMetrics.rowHeight + tableMetrics.headerHeight + 1, 180), 320)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

private struct UsageHistoryHeaderTitles: Equatable {
    var date: String
    var model: String
    var input: String
    var output: String
    var total: String
    var cost: String
}

private struct UsageHistoryDisplayRow: Identifiable, Equatable {
    var id: String
    var date: String
    var model: String
    var input: String
    var output: String
    var total: String
    var cost: String
    var striped: Bool
}

private struct UsageHistoryTableMetrics: Equatable {
    var dateWidth: CGFloat
    var modelWidth: CGFloat
    var metricWidth: CGFloat
    var costWidth: CGFloat
    var horizontalPadding: CGFloat = 8
    var headerHeight: CGFloat = 36
    var rowHeight: CGFloat = 34

    var leftContentWidth: CGFloat { dateWidth + modelWidth }
    var leftViewportWidth: CGFloat { leftContentWidth + (horizontalPadding * 2) }
    var rightContentWidth: CGFloat { (metricWidth * 3) + costWidth }
    var rightDocumentWidth: CGFloat { rightContentWidth + (horizontalPadding * 2) }
}

private struct FrozenUsageHistoryTable: NSViewRepresentable {
    let rows: [UsageHistoryDisplayRow]
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    func makeNSView(context: Context) -> FrozenUsageHistoryTableContainer {
        let container = FrozenUsageHistoryTableContainer(metrics: metrics)
        container.update(rows: rows, titles: titles, metrics: metrics)
        return container
    }

    func updateNSView(_ nsView: FrozenUsageHistoryTableContainer, context: Context) {
        nsView.update(rows: rows, titles: titles, metrics: metrics)
    }
}

private final class FrozenUsageForwardingViewport: NSView {
    weak var targetScrollView: NSScrollView?

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if let targetScrollView {
            targetScrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private final class FrozenUsageHistoryTableContainer: NSView {
    private let headerLeftViewport = FrozenUsageForwardingViewport()
    private let headerRightViewport = FrozenUsageForwardingViewport()
    private let leftBodyViewport = FrozenUsageForwardingViewport()
    private let rightBodyScrollView = NSScrollView()

    private let headerLeftHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let headerRightHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let leftBodyHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let rightBodyHost = NSHostingView(rootView: AnyView(EmptyView()))

    private var metrics: UsageHistoryTableMetrics
    private var rows: [UsageHistoryDisplayRow] = []
    private var boundsObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(metrics: UsageHistoryTableMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func update(rows: [UsageHistoryDisplayRow], titles: UsageHistoryHeaderTitles, metrics: UsageHistoryTableMetrics) {
        self.rows = rows
        self.metrics = metrics

        headerLeftHost.rootView = AnyView(
            FrozenUsageHeaderLeftView(titles: titles, metrics: metrics)
        )
        headerRightHost.rootView = AnyView(
            FrozenUsageHeaderRightView(titles: titles, metrics: metrics)
        )
        leftBodyHost.rootView = AnyView(
            FrozenUsageBodyLeftView(rows: rows, metrics: metrics)
        )
        rightBodyHost.rootView = AnyView(
            FrozenUsageBodyRightView(rows: rows, metrics: metrics)
        )

        needsLayout = true
        layoutSubtreeIfNeeded()
        syncFrozenOffsets()
    }

    override func layout() {
        super.layout()

        let leftWidth = metrics.leftViewportWidth
        let headerHeight = metrics.headerHeight
        let totalWidth = bounds.width
        let totalHeight = bounds.height
        let bodyHeight = max(totalHeight - headerHeight, 0)
        let rightWidth = max(totalWidth - leftWidth, 0)
        let contentHeight = max(CGFloat(rows.count) * metrics.rowHeight, bodyHeight)

        headerLeftViewport.frame = CGRect(x: 0, y: 0, width: leftWidth, height: headerHeight)
        headerRightViewport.frame = CGRect(x: leftWidth, y: 0, width: rightWidth, height: headerHeight)
        leftBodyViewport.frame = CGRect(x: 0, y: headerHeight, width: leftWidth, height: bodyHeight)
        rightBodyScrollView.frame = CGRect(x: leftWidth, y: headerHeight, width: rightWidth, height: bodyHeight)

        headerLeftHost.frame = CGRect(x: 0, y: 0, width: leftWidth, height: headerHeight)
        headerRightHost.frame = CGRect(x: -rightBodyScrollView.contentView.bounds.origin.x, y: 0, width: metrics.rightDocumentWidth, height: headerHeight)
        leftBodyHost.frame = CGRect(x: 0, y: -rightBodyScrollView.contentView.bounds.origin.y, width: leftWidth, height: contentHeight)
        rightBodyHost.frame = CGRect(x: 0, y: 0, width: metrics.rightDocumentWidth, height: contentHeight)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor

        [headerLeftViewport, headerRightViewport, leftBodyViewport].forEach { viewport in
            viewport.wantsLayer = true
            viewport.layer?.masksToBounds = true
            viewport.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(viewport)
        }

        rightBodyScrollView.wantsLayer = true
        rightBodyScrollView.layer?.backgroundColor = NSColor.clear.cgColor
        rightBodyScrollView.drawsBackground = false
        rightBodyScrollView.borderType = .noBorder
        rightBodyScrollView.hasVerticalScroller = true
        rightBodyScrollView.hasHorizontalScroller = true
        rightBodyScrollView.autohidesScrollers = true
        rightBodyScrollView.scrollerStyle = .overlay
        rightBodyScrollView.contentView.postsBoundsChangedNotifications = true
        rightBodyScrollView.contentView.wantsLayer = true
        rightBodyScrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        rightBodyScrollView.documentView = rightBodyHost
        rightBodyScrollView.verticalScroller?.knobStyle = .light
        rightBodyScrollView.horizontalScroller?.knobStyle = .light
        rightBodyHost.wantsLayer = true
        rightBodyHost.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(rightBodyScrollView)

        headerRightViewport.targetScrollView = rightBodyScrollView
        leftBodyViewport.targetScrollView = rightBodyScrollView

        headerLeftViewport.addSubview(headerLeftHost)
        headerRightViewport.addSubview(headerRightHost)
        leftBodyViewport.addSubview(leftBodyHost)

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: rightBodyScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.syncFrozenOffsets()
        }
    }

    private func syncFrozenOffsets() {
        let bounds = rightBodyScrollView.contentView.bounds
        headerRightHost.frame.origin.x = -bounds.origin.x
        leftBodyHost.frame.origin.y = -bounds.origin.y
    }
}

private struct FrozenUsageHeaderLeftView: View {
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        HStack(spacing: 0) {
            headerCell(titles.date, width: metrics.dateWidth, alignment: .leading)
            headerCell(titles.model, width: metrics.modelWidth, alignment: .leading)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: metrics.leftViewportWidth, height: metrics.headerHeight, alignment: .leading)
        .background(Color.white.opacity(0.05))
    }
}

private struct FrozenUsageHeaderRightView: View {
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        HStack(spacing: 0) {
            headerCell(titles.input, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.output, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.total, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.cost, width: metrics.costWidth, alignment: .trailing)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: metrics.rightDocumentWidth, height: metrics.headerHeight, alignment: .leading)
        .background(Color.white.opacity(0.05))
    }
}

private struct FrozenUsageBodyLeftView: View {
    let rows: [UsageHistoryDisplayRow]
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    valueCell(row.date, width: metrics.dateWidth, alignment: .leading, weight: .medium)
                    valueCell(row.model, width: metrics.modelWidth, alignment: .leading)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(width: metrics.leftViewportWidth, height: metrics.rowHeight, alignment: .leading)
                .background(row.striped ? Color.white.opacity(0.025) : Color.clear)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.04))
                }
            }
        }
        .frame(width: metrics.leftViewportWidth, alignment: .topLeading)
    }
}

private struct FrozenUsageBodyRightView: View {
    let rows: [UsageHistoryDisplayRow]
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    valueCell(row.input, width: metrics.metricWidth, alignment: .trailing, weight: .medium)
                    valueCell(row.output, width: metrics.metricWidth, alignment: .trailing, weight: .medium)
                    valueCell(row.total, width: metrics.metricWidth, alignment: .trailing, weight: .semibold)
                    valueCell(row.cost, width: metrics.costWidth, alignment: .trailing, weight: .medium)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(width: metrics.rightDocumentWidth, height: metrics.rowHeight, alignment: .leading)
                .background(row.striped ? Color.white.opacity(0.025) : Color.clear)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.04))
                }
            }
        }
        .frame(width: metrics.rightDocumentWidth, alignment: .topLeading)
    }
}

private func headerCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
    Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: width, alignment: alignment)
}

private func valueCell(
    _ value: String,
    width: CGFloat,
    alignment: Alignment,
    weight: Font.Weight = .regular
) -> some View {
    Text(value)
        .font(.system(size: 11, weight: weight, design: .monospaced))
        .lineLimit(1)
        .truncationMode(alignment == .leading ? .middle : .head)
        .frame(width: width, alignment: alignment)
}

private struct CodexManagedAccountRow: View {
    @ObservedObject private var l10n = L10n.shared
    let account: CodexManagedAccount
    let isActive: Bool
    let onActivate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                        if isActive {
                            Text(l10n["codex_account_active_badge"])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green.opacity(0.12))
                                )
                        }
                    }
                    Text(account.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(account.accountKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 8) {
                    if !isActive {
                        Button(l10n["codex_account_activate"]) {
                            onActivate()
                        }
                        .buttonStyle(.link)
                    }
                    Button(l10n["codex_account_remove"], role: .destructive) {
                        onRemove()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Appearance Page

private struct AppearancePage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.notchWidthOverride) private var notchWidthOverride = SettingsDefaults.notchWidthOverride
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions
    @AppStorage(SettingsKey.sessionGroupingMode) private var sessionGroupingMode = SettingsDefaults.sessionGroupingMode
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    private var customNotchWidthEnabled: Binding<Bool> {
        Binding(
            get: { notchWidthOverride > 0 },
            set: { enabled in
                if enabled {
                    notchWidthOverride = max(
                        ScreenDetector.defaultManualNotchWidth(),
                        120
                    )
                } else {
                    notchWidthOverride = 0
                }
            }
        )
    }

    var body: some View {
        Form {
            Section(l10n["preview"]) {
                AppearancePreview(
                    fontSize: contentFontSize,
                    lineLimit: aiMessageLines,
                    showDetails: showAgentDetails
                )
            }

            Section(l10n["panel"]) {
                Toggle(l10n["custom_notch_width"], isOn: customNotchWidthEnabled)
                if notchWidthOverride > 0 {
                    HStack {
                        Text(l10n["notch_width"])
                        Spacer()
                        Text("\(notchWidthOverride) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(notchWidthOverride) },
                            set: { notchWidthOverride = Int($0) }
                        ),
                        in: 120...360,
                        step: 1
                    )
                }
                Text(l10n["notch_width_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(selection: $maxVisibleSessions) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text(l10n["unlimited"]).tag(99)
                } label: {
                    Text(l10n["max_visible_sessions"])
                    Text(l10n["max_visible_sessions_desc"])
                }

                Picker(l10n["session_grouping"], selection: $sessionGroupingMode) {
                    Text(l10n["group_all"]).tag("all")
                    Text(l10n["group_project"]).tag("project")
                    Text(l10n["group_status"]).tag("status")
                    Text(l10n["group_cli"]).tag("cli")
                }
            }

            Section(l10n["content"]) {
                Picker(l10n["content_font_size"], selection: $contentFontSize) {
                    Text("10pt").tag(10)
                    Text(l10n["11pt_default"]).tag(11)
                    Text("12pt").tag(12)
                    Text("13pt").tag(13)
                }
                Picker(l10n["ai_reply_lines"], selection: $aiMessageLines) {
                    Text(l10n["1_line_default"]).tag(1)
                    Text(l10n["2_lines"]).tag(2)
                    Text(l10n["3_lines"]).tag(3)
                    Text(l10n["5_lines"]).tag(5)
                    Text(l10n["unlimited"]).tag(0)
                }
                Toggle(l10n["show_agent_details"], isOn: $showAgentDetails)
                Toggle(l10n["show_tool_status"], isOn: $showToolStatus)
            }
        }
        .formStyle(.grouped)
    }
}

/// Live preview mimicking the real SessionCard layout.
private struct AppearancePreview: View {
    let fontSize: Int
    let lineLimit: Int
    let showDetails: Bool

    private var fs: CGFloat { CGFloat(fontSize) }
    private let green = Color(red: 0.3, green: 0.85, blue: 0.4)
    private let aiColor = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Column 1: Mascot
            VStack(spacing: 3) {
                MascotView(source: "claude", status: .processing, size: 32)
                if showDetails {
                    HStack(spacing: 1) {
                        MiniAgentIcon(active: true, size: 8)
                        MiniAgentIcon(active: false, size: 8)
                    }
                }
            }
            .frame(width: 36)

            // Column 2: Content
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Text("my-project")
                        .font(.system(size: fs + 2, weight: .bold, design: .monospaced))
                        .foregroundStyle(green)
                    Spacer()
                    Text("3m")
                        .font(.system(size: max(9, fs - 1.5), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
                }

                // Chat
                VStack(alignment: .leading, spacing: 3) {
                    // User prompt
                    HStack(alignment: .top, spacing: 4) {
                        Text(">")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(green)
                        Text("Fix the login bug")
                            .font(.system(size: fs, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    // AI reply
                    HStack(alignment: .top, spacing: 4) {
                        Text("$")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(aiColor)
                        Text("I've analyzed the codebase and found the issue in the authentication module. The token validation was skipping the expiry check when refreshing sessions.")
                            .font(.system(size: fs, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(lineLimit > 0 ? lineLimit : nil)
                            .truncationMode(.tail)
                    }
                    // Working indicator
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(aiColor)
                        Text("Edit src/auth.ts")
                            .font(.system(size: fs, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.05))
        )
        .animation(.easeInOut(duration: 0.25), value: fontSize)
        .animation(.easeInOut(duration: 0.25), value: lineLimit)
        .animation(.easeInOut(duration: 0.25), value: showDetails)
    }
}

// MARK: - Mascots Page

private struct MascotsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var previewStatus: AgentStatus = .processing
    @AppStorage(SettingsKey.mascotSpeed) private var mascotSpeed = SettingsDefaults.mascotSpeed
    @AppStorage(SettingsKey.mascotOverridesVersion) private var mascotOverridesVersion = 0

    private let automaticSelection = "__auto__"

    private let mascotList: [(name: String, source: String, desc: String, color: Color)] = [
        ("Clawd", "claude", "Claude Code", Color(red: 0.871, green: 0.533, blue: 0.427)),
        ("Dex", "codex", "Codex (OpenAI)", Color(red: 0.92, green: 0.92, blue: 0.93)),
        ("Gemini", "gemini", "Gemini CLI", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("CursorBot", "cursor", "Cursor", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("CopilotBot", "copilot", "GitHub Copilot", Color(red: 0.35, green: 0.75, blue: 0.95)),
        ("QoderBot", "qoder", "Qoder", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("Droid", "droid", "Factory", Color(red: 0.835, green: 0.416, blue: 0.149)),
        ("Buddy", "codebuddy", "CodeBuddy", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("OpBot", "opencode", "OpenCode", Color(red: 0.55, green: 0.55, blue: 0.57)),
    ]

    var body: some View {
        Form {
            Section {
                Picker(l10n["preview_status"], selection: $previewStatus) {
                    Text(l10n["processing"]).tag(AgentStatus.processing)
                    Text(l10n["idle"]).tag(AgentStatus.idle)
                    Text(l10n["waiting_approval"]).tag(AgentStatus.waitingApproval)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(l10n["mascot_speed"])
                    Spacer()
                    Text(mascotSpeed == 0
                         ? l10n["speed_off"]
                         : String(format: "%.1f×", Double(mascotSpeed) / 100.0))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(mascotSpeed) },
                    set: { mascotSpeed = Int($0) }
                ), in: 0...300, step: 25)
            }

            Section {
                HStack {
                    Text("Per-client mascot override")
                    Spacer()
                    Text("\(MascotOverrides.customizedCount()) customized")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if MascotOverrides.customizedCount() > 0 {
                    Button("Reset all mascot overrides", role: .destructive) {
                        MascotOverrides.resetAll()
                    }
                }
            }

            Section {
                ForEach(mascotList, id: \.source) { mascot in
                    MascotRow(
                        name: mascot.name,
                        source: mascot.source,
                        desc: mascot.desc,
                        color: mascot.color,
                        status: previewStatus
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MascotRow: View {
    let name: String
    let source: String
    let desc: String
    let color: Color
    let status: AgentStatus
    @AppStorage(SettingsKey.mascotOverridesVersion) private var mascotOverridesVersion = 0

    private let automaticSelection = "__auto__"

    private var selection: Binding<String> {
        Binding(
            get: { MascotOverrides.override(for: source) ?? automaticSelection },
            set: { newValue in
                let override = newValue == automaticSelection ? nil : newValue
                MascotOverrides.setOverride(override, for: source)
            }
        )
    }

    private var effectiveSource: String {
        MascotOverrides.effectiveSource(for: source)
    }

    private var isCustomized: Bool {
        MascotOverrides.override(for: source) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 56, height: 56)
                    MascotView(source: source, status: status, size: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        if let icon = cliIcon(source: source, size: 16) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        if isCustomized {
                            Text("custom")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(0.12))
                                )
                        }
                    }
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if effectiveSource != source {
                        Text("Using \(effectiveSource.capitalized) mascot")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            Picker("Mascot", selection: selection) {
                Text("Follow default").tag(automaticSelection)
                Text("Clawd").tag("claude")
                Text("Dex").tag("codex")
                Text("Gemini").tag("gemini")
                Text("CursorBot").tag("cursor")
                Text("CopilotBot").tag("copilot")
                Text("QoderBot").tag("qoder")
                Text("Droid").tag("droid")
                Text("Buddy").tag("codebuddy")
                Text("OpBot").tag("opencode")
            }

            if isCustomized {
                Button("Reset this override") {
                    MascotOverrides.setOverride(nil, for: source)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sound Page

private struct SoundPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = SettingsDefaults.soundVolume
    @AppStorage(SettingsKey.soundSessionStart) private var soundSessionStart = SettingsDefaults.soundSessionStart
    @AppStorage(SettingsKey.soundTaskComplete) private var soundTaskComplete = SettingsDefaults.soundTaskComplete
    @AppStorage(SettingsKey.soundTaskError) private var soundTaskError = SettingsDefaults.soundTaskError
    @AppStorage(SettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = SettingsDefaults.soundApprovalNeeded
    @AppStorage(SettingsKey.soundPromptSubmit) private var soundPromptSubmit = SettingsDefaults.soundPromptSubmit
    @AppStorage(SettingsKey.soundBoot) private var soundBoot = SettingsDefaults.soundBoot
    @AppStorage(SettingsKey.soundPackID) private var soundPackID = SettingsDefaults.soundPackID
    @State private var soundPacks: [SoundPack] = SoundPackCatalog.discoverPacks()
    @State private var registryEntries: [SoundPackRegistryEntry] = SoundPackRegistry.loadCachedEntries()
    @State private var isRefreshingRegistry = false
    @State private var installingRegistryIDs: Set<String> = []
    @State private var registryStatusMessage = ""
    @State private var registryStatusIsError = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n["enable_sound"], isOn: $soundEnabled)
                if soundEnabled {
                    HStack(spacing: 8) {
                        Text(l10n["volume"])
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(soundVolume) },
                                set: { soundVolume = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(soundVolume)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    Picker(l10n["sound_pack"], selection: $soundPackID) {
                        ForEach(soundPacks) { pack in
                            Text(pack.title).tag(pack.id)
                        }
                    }

                    HStack(spacing: 8) {
                        if let selectedPack = soundPacks.first(where: { $0.id == soundPackID }) {
                            Text(selectedPack.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(l10n["open_sound_pack_folder"]) {
                            SoundPackCatalog.openUserPackRoot()
                            refreshSoundPacks()
                        }
                        .buttonStyle(.link)

                        Button(isRefreshingRegistry ? l10n["sound_pack_syncing"] : l10n["sound_pack_sync"]) {
                            refreshRegistry()
                        }
                        .buttonStyle(.link)
                        .disabled(isRefreshingRegistry)
                    }
                }
            }

            if !registryEntries.isEmpty || !registryStatusMessage.isEmpty {
                Section(l10n["sound_pack_catalog"]) {
                    if !registryStatusMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: registryStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(registryStatusIsError ? .red : .green)
                            Text(registryStatusMessage)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(registryEntries) { entry in
                        RegistrySoundPackRow(
                            entry: entry,
                            isInstalled: soundPacks.contains(where: { $0.id == entry.id }),
                            isInstalling: installingRegistryIDs.contains(entry.id),
                            isSelected: soundPackID == entry.id
                        ) {
                            useOrInstall(entry)
                        }
                    }
                }
            }

            if soundEnabled {
                Section(l10n["sessions"]) {
                    SoundEventRow(title: l10n["session_start"], subtitle: l10n["new_claude_session"], cue: .sessionStart, isOn: $soundSessionStart)
                    SoundEventRow(title: l10n["task_complete"], subtitle: l10n["ai_completed_reply"], cue: .taskComplete, isOn: $soundTaskComplete)
                    SoundEventRow(title: l10n["task_error"], subtitle: l10n["tool_or_api_error"], cue: .taskError, isOn: $soundTaskError)
                }

                Section(l10n["interaction"]) {
                    SoundEventRow(title: l10n["approval_needed"], subtitle: l10n["waiting_approval_desc"], cue: .inputRequired, isOn: $soundApprovalNeeded)
                    SoundEventRow(title: l10n["task_confirmation"], subtitle: l10n["you_sent_message"], cue: .taskAcknowledge, isOn: $soundPromptSubmit)
                }

                Section(l10n["system_section"]) {
                    BootSoundRow(title: l10n["boot_sound"], subtitle: l10n["boot_sound_desc"], isOn: $soundBoot)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshSoundPacks()
            registryEntries = SoundPackRegistry.loadCachedEntries()
        }
    }

    private func refreshSoundPacks() {
        soundPacks = SoundPackCatalog.discoverPacks()
        if !soundPacks.contains(where: { $0.id == soundPackID }) {
            soundPackID = SettingsDefaults.soundPackID
        }
    }

    private func refreshRegistry() {
        isRefreshingRegistry = true
        registryStatusMessage = ""
        registryStatusIsError = false

        Task {
            do {
                let entries = try await SoundPackRegistry.refreshEntries()
                await MainActor.run {
                    registryEntries = entries
                    isRefreshingRegistry = false
                    registryStatusMessage = l10n["sound_pack_sync_complete"]
                    registryStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    isRefreshingRegistry = false
                    registryStatusMessage = error.localizedDescription
                    registryStatusIsError = true
                }
            }
        }
    }

    private func useOrInstall(_ entry: SoundPackRegistryEntry) {
        if soundPacks.contains(where: { $0.id == entry.id }) {
            soundPackID = entry.id
            return
        }

        installingRegistryIDs.insert(entry.id)
        registryStatusMessage = ""

        Task {
            do {
                _ = try await SoundPackRegistry.install(entry: entry)
                await MainActor.run {
                    installingRegistryIDs.remove(entry.id)
                    refreshSoundPacks()
                    soundPackID = entry.id
                    registryStatusMessage = l10n["sound_pack_install_complete"]
                    registryStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    installingRegistryIDs.remove(entry.id)
                    registryStatusMessage = error.localizedDescription
                    registryStatusIsError = true
                }
            }
        }
    }
}

private struct SoundEventRow: View {
    let title: String
    var subtitle: String? = nil
    let cue: SoundCue
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            Button {
                SoundManager.shared.preview(cue: cue)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct BootSoundRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            Button {
                SoundManager.shared.previewBoot()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct RegistrySoundPackRow: View {
    let entry: SoundPackRegistryEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        color(from: entry.accentHex) ?? .blue
    }

    private var actionTitle: String {
        if isInstalling {
            return L10n.shared["sound_pack_installing"]
        }
        if isInstalled {
            return isSelected ? L10n.shared["sound_pack_in_use"] : L10n.shared["sound_pack_use"]
        }
        return L10n.shared["sound_pack_install"]
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.systemName)
                .frame(width: 20)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                    Text(entry.trustLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(accent.opacity(0.12)))
                }

                Text(entry.compactMeta)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isInstalling)
        }
    }

    private func color(from hex: String) -> Color? {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

// MARK: - About Page

private struct AboutPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                AppLogoView(size: 100)

                VStack(spacing: 6) {
                    Text("SuperIsland")
                        .font(.system(size: 26, weight: .bold))
                    Text("Version \(AppVersion.current)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(l10n["about_desc1"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(l10n["about_desc2"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    aboutLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/zhy19950705/SuperIsland")
                    aboutLink("Issues", icon: "ladybug", url: "https://github.com/zhy19950705/SuperIsland/issues")
                }

                Button {
                    UpdateChecker.shared.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(l10n["check_for_updates"])
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }

    private func aboutLink(_ title: String, icon: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Behavior Animation Previews

private enum BehaviorAnim {
    case hideFullscreen, hideNoSession, smartSuppress, collapseMouseLeave
}

private struct BehaviorToggleRow: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool
    let animation: BehaviorAnim

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                NotchMiniAnim(animation: animation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(desc)
                }
            }
        }
    }
}

/// Canvas-based notch animation with smooth interpolation.
private struct NotchMiniAnim: View {
    let animation: BehaviorAnim
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
            Canvas { c, sz in
                draw(c, sz: sz, t: ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 72, height: 48)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(min(1, max(0, t)))
    }

    private func draw(_ c: GraphicsContext, sz: CGSize, t: Double) {
        switch animation {
        case .hideFullscreen:   drawFullscreen(c, sz: sz, t: t)
        case .hideNoSession:    drawNoSession(c, sz: sz, t: t)
        case .smartSuppress:    drawSuppress(c, sz: sz, t: t)
        case .collapseMouseLeave: drawMouseLeave(c, sz: sz, t: t)
        }
    }

    /// Draw a notch pill: smooth w/h/opacity, with orange eyes + content lines when expanded.
    private func drawPill(_ c: GraphicsContext, sz: CGSize,
                          w: CGFloat, h: CGFloat, op: Double,
                          flashColor: Color? = nil) {
        guard op > 0.01 else { return }
        let x = (sz.width - w) / 2
        let r = min(w, h) * 0.45
        let rect = CGRect(x: x, y: 0, width: w, height: h)
        let pill = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        c.fill(pill, with: .color(Color(white: 0.06).opacity(op)))

        // Eyes — always visible when notch is visible
        let eyeSize: CGFloat = h > 16 ? 3.5 : 2.5
        let eyeY: CGFloat = h > 16 ? 5 : max(2, (h - eyeSize) / 2)
        let eyeGap: CGFloat = h > 16 ? 5 : 3
        c.fill(Path(CGRect(x: sz.width / 2 - eyeGap - eyeSize / 2, y: eyeY,
                           width: eyeSize, height: eyeSize)),
               with: .color(orange.opacity(op)))
        c.fill(Path(CGRect(x: sz.width / 2 + eyeGap - eyeSize / 2, y: eyeY,
                           width: eyeSize, height: eyeSize)),
               with: .color(orange.opacity(op)))

        // Content lines — only when expanded
        if h > 16 {
            let contentOp = op * Double(min(1, (h - 16) / 10))
            let lx = x + 6
            let widths: [CGFloat] = [w * 0.6, w * 0.45, w * 0.55]
            for (i, lw) in widths.enumerated() {
                let ly = 12 + CGFloat(i) * 5
                if ly + 2 < h - 3 {
                    c.fill(Path(CGRect(x: lx, y: ly, width: lw, height: 2)),
                           with: .color(.white.opacity(0.3 * contentOp * (1 - Double(i) * 0.2))))
                }
            }
        }

        // Flash overlay
        if let color = flashColor {
            c.fill(pill, with: .color(color))
        }
    }

    // 1) Fullscreen: notch visible → screen dims → notch fades → restore
    private func drawFullscreen(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let vis: Double = cycle < 0.3 ? 1.0 :
            cycle < 0.45 ? 1.0 - (cycle - 0.3) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        // Fullscreen dimming overlay
        if vis < 0.95 {
            c.fill(Path(CGRect(origin: .zero, size: sz)),
                   with: .color(Color(white: 0.08).opacity(0.85 * (1 - vis))))
            // Fullscreen icon
            let iconOp = cycle > 0.45 && cycle < 0.65 ?
                sin((cycle - 0.45) / 0.2 * .pi) * 0.5 : 0
            if iconOp > 0.01 {
                c.draw(Text("⛶").font(.system(size: 16)).foregroundColor(.white.opacity(iconOp)),
                       at: CGPoint(x: sz.width / 2, y: sz.height / 2 + 2))
            }
        }
        drawPill(c, sz: sz, w: 28, h: 10, op: vis)
    }

    // 2) No session: green dots vanish → notch fades
    private func drawNoSession(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let dotOp: Double = cycle < 0.25 ? 1.0 :
            cycle < 0.4 ? 1.0 - (cycle - 0.25) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        let pillOp: Double = cycle < 0.35 ? 1.0 :
            cycle < 0.55 ? 1.0 - (cycle - 0.35) / 0.2 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)

        drawPill(c, sz: sz, w: 28, h: 10, op: pillOp)
        // Green session dots
        if dotOp > 0.01 {
            let cx = sz.width / 2
            for i in 0..<2 {
                let dx: CGFloat = CGFloat(i) * 6 - 3
                c.fill(Path(ellipseIn: CGRect(x: cx + dx - 1.5, y: 3, width: 3, height: 3)),
                       with: .color(.green.opacity(0.85 * dotOp * pillOp)))
            }
        }
    }

    // 3) Smart suppress: event flash → notch pulses but stays collapsed → × indicator
    private func drawSuppress(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        // Two event pulses
        let p1 = (cycle > 0.15 && cycle < 0.4) ? sin((cycle - 0.15) / 0.25 * .pi) : 0.0
        let p2 = (cycle > 0.55 && cycle < 0.75) ? sin((cycle - 0.55) / 0.2 * .pi) : 0.0
        let pulse = max(p1, p2)
        let pw = 28 + CGFloat(pulse) * 8
        let ph: CGFloat = 10 + CGFloat(pulse) * 3

        let flashColor: Color? = pulse > 0.05 ? .green.opacity(0.3 * pulse) : nil
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0, flashColor: flashColor)

        // × suppress indicator
        let xOp1 = (cycle > 0.3 && cycle < 0.48) ? sin((cycle - 0.3) / 0.18 * .pi) : 0.0
        let xOp2 = (cycle > 0.68 && cycle < 0.82) ? sin((cycle - 0.68) / 0.14 * .pi) : 0.0
        let xOp = max(xOp1, xOp2)
        if xOp > 0.01 {
            c.draw(Text("✕").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange.opacity(0.7 * xOp)),
                   at: CGPoint(x: sz.width / 2, y: 18))
        }
    }

    // 4) Mouse leave: cursor enters → expand → cursor leaves → collapse
    private func drawMouseLeave(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        // Expand amount: 0→1→0
        let expand: Double = cycle < 0.12 ? 0 :
            cycle < 0.25 ? (cycle - 0.12) / 0.13 :
            cycle < 0.5 ? 1.0 :
            cycle < 0.65 ? 1.0 - (cycle - 0.5) / 0.15 : 0

        let pw = lerp(28, 64, expand)
        let ph = lerp(10, 34, expand)
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0)

        // Mouse cursor
        let cursorPhase = cycle
        let cursorVis = cursorPhase > 0.05 && cursorPhase < 0.68
        if cursorVis {
            let cx: CGFloat, cy: CGFloat
            if cursorPhase < 0.12 {
                // Moving toward notch
                let t = (cursorPhase - 0.05) / 0.07
                cx = lerp(sz.width / 2 + 15, sz.width / 2 + 2, t)
                cy = lerp(sz.height - 5, 8, t)
            } else if cursorPhase < 0.5 {
                // Hovering near notch
                cx = sz.width / 2 + 2
                cy = lerp(8, 6, expand)
            } else {
                // Moving away
                let t = (cursorPhase - 0.5) / 0.18
                cx = lerp(sz.width / 2 + 2, sz.width - 2, min(1, t))
                cy = lerp(6, sz.height - 2, min(1, t))
            }
            // Draw cursor arrow
            var arrow = Path()
            arrow.move(to: CGPoint(x: cx, y: cy))
            arrow.addLine(to: CGPoint(x: cx, y: cy + 8))
            arrow.addLine(to: CGPoint(x: cx + 2.5, y: cy + 6))
            arrow.addLine(to: CGPoint(x: cx + 5.5, y: cy + 6))
            arrow.closeSubpath()
            c.fill(arrow, with: .color(.white.opacity(0.9)))
            c.stroke(arrow, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
        }
    }
}

// MARK: - App Logo

struct AppLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        Canvas { ctx, sz in
            // macOS icon standard: ~10% padding on each side
            let inset = sz.width * 0.1
            let contentRect = CGRect(x: inset, y: inset, width: sz.width - inset * 2, height: sz.height - inset * 2)
            let px = contentRect.width / 16
            if showBackground {
                let bgPath = Path(roundedRect: contentRect, cornerRadius: contentRect.width * 0.22, style: .continuous)
                ctx.fill(bgPath, with: .color(.white))
            }
            // Notch pill
            let pillColor = showBackground ? Color(white: 0.1) : Color(white: 0.5)
            let pillRect = CGRect(x: contentRect.minX + px * 3, y: contentRect.minY + px * 6, width: px * 10, height: px * 4)
            ctx.fill(Path(roundedRect: pillRect, cornerRadius: px * 2, style: .continuous), with: .color(pillColor))
            // Eyes
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 5, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 9, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            // Pupils
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 6, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 10, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(showBackground ? 0.15 : 0), radius: size * 0.12, y: size * 0.04)
    }
}

// MARK: - Shortcuts Page

private struct ShortcutsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var recordingAction: ShortcutAction?
    @State private var eventMonitor: Any?
    @State private var refreshKey = 0

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(
                        action: action,
                        isRecording: recordingAction == action,
                        onStartRecording: { startRecording(action) },
                        onClear: { clearBinding(action) }
                    )
                    .id("\(action.rawValue)-\(refreshKey)")
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape — cancel
                self.stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
                return nil
            }
            action.setBinding(keyCode: event.keyCode, modifiers: mods)
            if !action.isEnabled { action.setEnabled(true) }
            self.stopRecording()
            self.refreshKey += 1
            self.notifyChange()
            return nil
        }
    }

    private func clearBinding(_ action: ShortcutAction) {
        action.setEnabled(false)
        refreshKey += 1
        notifyChange()
    }

    private func stopRecording() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        recordingAction = nil
    }

    private func notifyChange() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.setupGlobalShortcut()
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onClear: () -> Void
    @ObservedObject private var l10n = L10n.shared

    private var conflict: ShortcutAction? { action.conflictingAction() }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n["shortcut_\(action.rawValue)"])
                Text(l10n["shortcut_\(action.rawValue)_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let conflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("\(l10n["shortcut_conflict"]) \(l10n["shortcut_\(conflict.rawValue)"])")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            if isRecording {
                Text(l10n["shortcut_recording"])
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(.orange, lineWidth: 1))
            } else if action.isEnabled {
                HStack(spacing: 6) {
                    Text(action.binding.displayString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .onTapGesture { onStartRecording() }

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(l10n["shortcut_none"])
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .onTapGesture { onStartRecording() }
            }
        }
        .contentShape(Rectangle())
    }
}
