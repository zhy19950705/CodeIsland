import SwiftUI
import SuperIslandCore

// MARK: - Mascot Animation Speed Environment

private struct MascotSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var mascotSpeed: Double {
        get { self[MascotSpeedKey.self] }
        set { self[MascotSpeedKey.self] = newValue }
    }
}

/// Routes a CLI source identifier to the correct pixel mascot view.
struct MascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    var animated = true
    @AppStorage(SettingsKey.mascotSpeed) private var speedPct = SettingsDefaults.mascotSpeed
    @AppStorage(SettingsKey.mascotOverridesVersion) private var overridesVersion = 0

    var body: some View {
        let mascotSource = MascotOverrides.effectiveSource(for: source)
        Group {
            switch mascotSource {
            case "codex":
                DexView(status: status, size: size, animated: animated)
            case "gemini":
                GeminiView(status: status, size: size, animated: animated)
            case "cursor":
                CursorView(status: status, size: size, animated: animated)
            case "copilot":
                CopilotView(status: status, size: size, animated: animated)
            case "qoder":
                QoderView(status: status, size: size, animated: animated)
            case "droid":
                DroidView(status: status, size: size, animated: animated)
            case "codebuddy":
                BuddyView(status: status, size: size, animated: animated)
            case "opencode":
                OpenCodeView(status: status, size: size, animated: animated)
            default:
                ClawdView(status: status, size: size, animated: animated)
            }
        }
        .environment(\.mascotSpeed, Double(speedPct) / 100.0)
    }
}
