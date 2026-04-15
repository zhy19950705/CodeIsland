import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Appearance Page

struct AppearancePage: View {
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

/// Live preview mimicking a completion-review session card.
private struct AppearancePreview: View {
    @ObservedObject private var l10n = L10n.shared
    let fontSize: Int
    let lineLimit: Int
    let showDetails: Bool

    private var fs: CGFloat { CGFloat(fontSize) }
    private let green = Color(red: 0.3, green: 0.85, blue: 0.4)
    private let aiColor = Color(red: 0.85, green: 0.47, blue: 0.34)
    private var previewLineLimit: Int? {
        guard lineLimit > 0 else { return nil }
        return max(lineLimit, 5)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Column 1: Mascot
            VStack(spacing: 3) {
                MascotView(source: "claude", status: .idle, size: 32)
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
                        .foregroundStyle(.white)
                    Spacer()
                    Text(l10n["completion_pending_review"])
                        .font(.system(size: max(9, fs - 1.5), weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.19, green: 0.58, blue: 0.91).opacity(0.78)))
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
                        Text("默认值改成 1 天")
                            .font(.system(size: fs, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    // AI reply
                    HStack(alignment: .top, spacing: 4) {
                        Text("$")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(aiColor)
                        Text("已改，默认值现在是 1 天。这个设置只会影响还没有写入 sessionTimeout 的用户；已经保存过该值的用户不会被自动迁移。")
                            .font(.system(size: fs, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(previewLineLimit)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
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
