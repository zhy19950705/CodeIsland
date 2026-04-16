import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Mascots Page

struct MascotsPage: View {
    @ObservedObject private var l10n = AppText.shared
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
                    Text(l10n["mascot_override_per_client"])
                    Spacer()
                    Text(String(format: l10n["mascot_override_customized"], MascotOverrides.customizedCount()))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if MascotOverrides.customizedCount() > 0 {
                    Button(l10n["mascot_reset_all_overrides"], role: .destructive) {
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
    // Reuse the shared Chinese copy catalog so the row stays consistent with the parent settings page.
    private let l10n = AppText.shared
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
                            Text(l10n["mascot_custom_badge"])
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
                        Text(String(format: l10n["mascot_using_override_format"], effectiveSource.capitalized))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            Picker(l10n["mascot_picker_title"], selection: selection) {
                Text(l10n["mascot_follow_default"]).tag(automaticSelection)
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
                Button(l10n["mascot_reset_override"]) {
                    MascotOverrides.setOverride(nil, for: source)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
