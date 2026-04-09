import SwiftUI
import CodeIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
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
    SidebarGroup(title: nil, pages: [.general, .behavior, .appearance, .mascots, .sound, .shortcuts]),
    SidebarGroup(title: "CodeIsland", pages: [.testing, .hooks, .about]),
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
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sidebarGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = group.title {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 2)
                            }

                            ForEach(group.pages) { page in
                                Button {
                                    selectedPage = page
                                } label: {
                                    SidebarRow(page: page, isSelected: selectedPage == page)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 208, idealWidth: 208, maxWidth: 208, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch selectedPage {
                case .general: GeneralPage()
                case .behavior: BehaviorPage()
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .shortcuts: ShortcutsPage()
                case .testing: TestingPage(appState: appState)
                case .hooks: HooksPage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    let isSelected: Bool

    var body: some View {
        Label {
            Text(l10n[page.rawValue])
                .font(.system(size: 13))
                .padding(.leading, 2)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - General Page

private struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @AppStorage(SettingsKey.allowHorizontalDrag) private var allowHorizontalDrag = SettingsDefaults.allowHorizontalDrag
    @State private var launchAtLogin: Bool
    @State private var usageSnapshot: UsageSnapshot = UsageSnapshotStore.load()
    @State private var usageMonitorSnapshot = UsageMonitorLaunchAgentManager().snapshot()
    @State private var usageStatusMessage = ""
    @State private var usageStatusIsError = false

    private let usageMonitorManager = UsageMonitorLaunchAgentManager()

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
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
                Picker(l10n["display"], selection: $displayChoice) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let name = screen.localizedName
                        let isBuiltin = name.contains("Built-in") || name.contains("内置")
                        let label = isBuiltin ? l10n["builtin_display"] : name
                        Text(label).tag("screen_\(index)")
                    }
                }
            }

            Section(l10n["usage_monitor_section"]) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n["usage_monitor"])
                    Text(usageMonitorSnapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        do {
                            try usageMonitorManager.setEnabled(usageMonitorSnapshot.state != .enabled)
                            refreshUsage()
                            usageStatusMessage = usageMonitorSnapshot.state == .enabled
                                ? l10n["usage_monitor_disabled"]
                                : l10n["usage_monitor_enabled"]
                            usageStatusIsError = false
                        } catch {
                            usageStatusMessage = error.localizedDescription
                            usageStatusIsError = true
                            refreshUsage()
                        }
                    } label: {
                        Text(usageMonitorSnapshot.state == .enabled ? l10n["disable_usage_monitor"] : l10n["enable_usage_monitor"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(usageMonitorSnapshot.state == .unavailable)

                    Button {
                        do {
                            try usageMonitorManager.runNow()
                            refreshUsage()
                            usageStatusMessage = l10n["usage_refresh_complete"]
                            usageStatusIsError = false
                        } catch {
                            usageStatusMessage = error.localizedDescription
                            usageStatusIsError = true
                        }
                    } label: {
                        Text(l10n["refresh_now"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(usageMonitorSnapshot.state == .unavailable)
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
        }
        .formStyle(.grouped)
        .onAppear { refreshUsage() }
        .onReceive(NotificationCenter.default.publisher(for: UsageSnapshotStore.didUpdateNotification)) { _ in
            refreshUsage()
        }
    }

    private func refreshUsage() {
        usageSnapshot = UsageSnapshotStore.load()
        usageMonitorSnapshot = usageMonitorManager.snapshot()
    }
}

// MARK: - Behavior Page

private struct BehaviorPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.hideInFullscreen) private var hideInFullscreen = SettingsDefaults.hideInFullscreen
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
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
            }

            Section(l10n["sessions"]) {
                Picker(selection: $sessionTimeout) {
                    Text(l10n["no_cleanup"]).tag(0)
                    Text(l10n["10_minutes"]).tag(10)
                    Text(l10n["30_minutes"]).tag(30)
                    Text(l10n["1_hour"]).tag(60)
                    Text(l10n["2_hours"]).tag(120)
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
    @State private var cliSnapshots: [CLIIntegrationSnapshot] = []
    @State private var editorSnapshots: [EditorBridgeSnapshot] = []
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = UUID()

    private let cliIntegrationManager = CLIIntegrationManager()
    private let editorBridgeManager = EditorBridgeManager()

    var body: some View {
        Form {
            Section(l10n["editor_bridges"]) {
                ForEach(editorSnapshots) { snapshot in
                    EditorBridgeRow(snapshot: snapshot) {
                        editorBridgeManager.openInstallLocation(for: snapshot.host)
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
        }
        .formStyle(.grouped)
        .onAppear { refreshDiagnostics() }
    }

    private func refreshDiagnostics() {
        cliSnapshots = cliIntegrationManager.snapshots()
        editorSnapshots = editorBridgeManager.snapshots()
        refreshKey = UUID()
    }
}

private struct EditorBridgeRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: EditorBridgeSnapshot
    let onOpen: () -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        }
        .padding(.vertical, 2)
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
}

// MARK: - Appearance Page

private struct AppearancePage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions
    @AppStorage(SettingsKey.sessionGroupingMode) private var sessionGroupingMode = SettingsDefaults.sessionGroupingMode
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

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

    var body: some View {
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
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
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
                    Text("CodeIsland")
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
                    aboutLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/wxtsky/CodeIsland")
                    aboutLink("Issues", icon: "ladybug", url: "https://github.com/wxtsky/CodeIsland/issues")
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
