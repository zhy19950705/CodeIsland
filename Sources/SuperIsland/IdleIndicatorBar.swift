import SwiftUI
import SuperIslandCore

struct IdleIndicatorBar: View {
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let hovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                NeonPixelCatView()
                    .opacity(hovered ? 1.0 : 0.72)
                MascotView(source: "claude", status: .idle, size: mascotSize)
                    .opacity(hovered ? 0.9 : 0.5)
                BuddyASCIIView()
                    .opacity(hovered ? 0.9 : 0.55)
            }
            .padding(.leading, 6)

            Spacer(minLength: hasNotch ? notchW : 0)

            if hovered {
                HStack(spacing: 8) {
                    BuddyASCIIView(tint: .white.opacity(0.8))

                    HStack(spacing: 4) {
                        // Reuse the expanded notch control cluster so idle hover state matches the active island state.
                        NotchControlButtonGroup(showsSoundToggle: true, trailingAction: .quitApp)
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
