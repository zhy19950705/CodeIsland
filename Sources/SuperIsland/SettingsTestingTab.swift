import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Testing Page

enum SettingsTestingScenario: String, CaseIterable, Identifiable {
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

struct TestingPage: View {
    @ObservedObject private var l10n = AppText.shared
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

                Button {
                    appState?.triggerTestingCompletionHook(mode: .simultaneous)
                    statusMessage = l10n["testing_simultaneous_completion_started"]
                    statusIsError = false
                } label: {
                    Text(l10n["testing_simultaneous_completion_button"])
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState == nil)

                Text(l10n["testing_simultaneous_completion_desc"])
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    appState?.triggerTestingCompletionHook(mode: .staggered)
                    statusMessage = l10n["testing_staggered_completion_started"]
                    statusIsError = false
                } label: {
                    Text(l10n["testing_staggered_completion_button"])
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState == nil)

                Text(l10n["testing_staggered_completion_desc"])
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
