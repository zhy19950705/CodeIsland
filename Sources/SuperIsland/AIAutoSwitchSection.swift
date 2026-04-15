import SwiftUI

// AIAutoSwitchSection isolates the launch-agent controls and threshold settings from the page-level async actions.
struct AIAutoSwitchSection: View {
    @ObservedObject private var l10n = L10n.shared
    let autoSwitchSnapshot: CodexAutoSwitchLaunchAgentSnapshot
    let isTogglingAutoSwitch: Bool
    let isRunningAutoSwitch: Bool
    let autoSwitch5hThreshold: Int
    let autoSwitchWeeklyThreshold: Int
    let autoSwitchAPIUsageEnabled: Bool
    let onToggleAutoSwitch: () -> Void
    let onRunAutoSwitch: () -> Void
    let onUpdateThreshold5h: (Int) -> Void
    let onUpdateThresholdWeekly: (Int) -> Void
    let onUpdateAPIUsage: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n["codex_auto_switch"])
                Text(autoSwitchSnapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    onToggleAutoSwitch()
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
                    onRunAutoSwitch()
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
                set: { onUpdateThreshold5h($0) }
            ), in: 0...100, step: 1) {
                Text("\(l10n["codex_auto_switch_threshold_5h"]) \(autoSwitch5hThreshold)%")
            }

            Stepper(value: Binding(
                get: { autoSwitchWeeklyThreshold },
                set: { onUpdateThresholdWeekly($0) }
            ), in: 0...100, step: 1) {
                Text("\(l10n["codex_auto_switch_threshold_weekly"]) \(autoSwitchWeeklyThreshold)%")
            }

            Toggle(l10n["codex_auto_switch_api_usage"], isOn: Binding(
                get: { autoSwitchAPIUsageEnabled },
                set: { onUpdateAPIUsage($0) }
            ))
        }
    }
}
