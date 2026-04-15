import SwiftUI
import AppKit
import SuperIslandCore

struct IdleIndicatorBar: View {
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let hovered: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                MascotView(source: "claude", status: .idle, size: mascotSize)
                    .opacity(hovered ? 0.9 : 0.5)
            }
            .padding(.leading, 6)

            Spacer(minLength: hasNotch ? notchW : 0)

            if hovered {
                HStack(spacing: 8) {
                    Text("0")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    HStack(spacing: 4) {
                        NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                            soundEnabled.toggle()
                        }
                        NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                            SettingsWindowController.shared.show()
                        }
                        NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .frame(height: notchHeight)
        .animation(NotchAnimation.micro, value: hovered)
    }
}

struct PixelButton: View {
    let label: String
    let fg: Color
    let bg: Color
    let border: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovering ? bg.opacity(1.5) : bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(hovering ? border : border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}

struct NotchIconButton: View {
    let icon: String
    var tint: Color = .white
    var tooltip: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(hovering ? 1.0 : 0.85))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(tint.opacity(hovering ? 0.2 : 0.08))
                )
                .scaleEffect(hovering ? 1.1 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .help(tooltip ?? "")
    }
}

// MARK: - Pixel Text (5x7 dot matrix style)
