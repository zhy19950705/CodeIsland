import SwiftUI
import AppKit
import SuperIslandCore

struct HoverApprovalActions: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.event.toolDescription ?? request.event.toolName ?? "Approval needed")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            HStack(spacing: 6) {
                PixelButton(
                    label: AppText.shared["deny"],
                    fg: .white.opacity(0.95),
                    bg: Color(red: 0.45, green: 0.12, blue: 0.12),
                    border: Color(red: 0.7, green: 0.25, blue: 0.25),
                    action: onDeny
                )
                PixelButton(
                    label: AppText.shared["allow_once"],
                    fg: .white.opacity(0.95),
                    bg: Color(red: 0.16, green: 0.38, blue: 0.18),
                    border: Color(red: 0.28, green: 0.62, blue: 0.32),
                    action: onAllow
                )
                PixelButton(
                    label: AppText.shared["always"],
                    fg: .white.opacity(0.95),
                    bg: Color(red: 0.14, green: 0.28, blue: 0.52),
                    border: Color(red: 0.28, green: 0.48, blue: 0.82),
                    action: onAlwaysAllow
                )
            }
        }
    }
}

struct HoverQuestionActions: View {
    let request: QuestionRequest
    @Binding var textInput: String
    let onAnswer: (String) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.question.question)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)

            if let options = request.question.options, !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                        let desc = request.question.descriptions?.indices.contains(idx) == true ? request.question.descriptions?[idx] : nil
                        Button {
                            onAnswer(option)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.88))
                                    if let desc, !desc.isEmpty {
                                        Text(desc)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.45))
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(">")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                    TextField(AppText.shared["type_answer"], text: $textInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .onSubmit {
                            let answer = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !answer.isEmpty {
                                onAnswer(answer)
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack(spacing: 6) {
                PixelButton(
                    label: AppText.shared["skip"],
                    fg: .white.opacity(0.6),
                    bg: Color.white.opacity(0.06),
                    border: Color.white.opacity(0.12),
                    action: onSkip
                )
                if request.question.options == nil || request.question.options?.isEmpty == true {
                    PixelButton(
                        label: AppText.shared["submit"],
                        fg: .white.opacity(0.95),
                        bg: Color(red: 0.16, green: 0.38, blue: 0.18),
                        border: Color(red: 0.28, green: 0.62, blue: 0.32),
                        action: {
                            let answer = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !answer.isEmpty {
                                onAnswer(answer)
                            }
                        }
                    )
                }
            }
        }
    }
}

struct NotchPanelShape: Shape {
    var shoulderExtension: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var minHeight: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                shoulderExtension,
                AnimatablePair(topCornerRadius, bottomCornerRadius)
            )
        }
        set {
            shoulderExtension = newValue.first
            topCornerRadius = newValue.second.first
            bottomCornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ext = shoulderExtension
        let maxY = max(rect.maxY, rect.minY + minHeight)
        let availableHeight = maxY - rect.minY
        let topRadius = min(topCornerRadius, rect.width / 4, availableHeight / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 4, availableHeight / 2)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX - ext, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + ext, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX + ext, y: rect.minY + topRadius * 0.18)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: maxY - bottomRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: maxY),
            control: CGPoint(x: rect.maxX, y: maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX - ext, y: rect.minY),
            control: CGPoint(x: rect.minX - ext, y: rect.minY + topRadius * 0.18)
        )
        p.closeSubpath()
        return p
    }
}

struct TerminalJumpAccessory: View {
    let session: SessionSnapshot
    let isHovered: Bool

    private let accent = Color(red: 0.3, green: 0.85, blue: 0.4)

    private static let sourceBundleIds: [String: String] = [
        "cursor": "com.todesktop.230313mzl4w4u92",
        "qoder": "com.qoder.ide",
        "droid": "com.factory.app",
        "codebuddy": "com.tencent.codebuddy",
        "codex": "com.openai.codex",
        "opencode": "ai.opencode.desktop",
    ]

    private static var termIconCache: [String: NSImage] = [:]

    private var termIcon: NSImage? {
        let bid = session.termBundleId ?? Self.sourceBundleIds[session.source]
        guard let bid else { return nil }
        if let cached = Self.termIconCache[bid] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.termIconCache[bid] = icon
        return icon
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.08 : 0.05), lineWidth: 1)
                    )
                if let icon = termIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 18, height: 18)

            Text(session.terminalName ?? "open")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent.opacity(isHovered ? 0.96 : 0.8))
                .lineLimit(1)

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white.opacity(isHovered ? 0.7 : 0.34))
                .offset(x: isHovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.09, green: 0.13, blue: 0.11).opacity(isHovered ? 0.96 : 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(isHovered ? 0.24 : 0.12), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SessionJumpButton: View {
    let session: SessionSnapshot
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        // Reuse the session-row accessory so notification cards keep the same
        // affordance and jump semantics as the list cards.
        Button(action: action) {
            TerminalJumpAccessory(session: session, isHovered: hovering)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { isHovered in
            withAnimation(NotchAnimation.micro) { hovering = isHovered }
        }
    }
}

struct NotificationSessionHeader: View {
    let session: SessionSnapshot?
    let onJump: (() -> Void)?

    var body: some View {
        if let session {
            HStack(spacing: 5) {
                if let icon = cliIcon(source: session.source, size: 12) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                if let cwd = session.cwd {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.5))
                    Text((cwd as NSString).lastPathComponent)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let onJump {
                    SessionJumpButton(session: session, action: onJump)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

struct SessionTag: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    init(_ text: String, color: Color = .white.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color.opacity(0.96))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.14), lineWidth: 1)
            )
    }
}

struct TypingIndicator: View {
    let fontSize: CGFloat
    var label: String? = nil
    var bright: Bool = false
    var color: Color? = nil
    @State private var phase: CGFloat = -60

    var body: some View {
        if let label {
            let baseColor: Color = color ?? .white
            let baseOpacity: Double = bright ? 0.6 : 0.35
            let peakOpacity: Double = bright ? 0.8 : 0.5
            let midOpacity: Double = bright ? 0.5 : 0.3
            let bandWidth: CGFloat = bright ? 80 : 60
            let duration: Double = 2.5
            let endPhase: CGFloat = bright ? 100 : 80
            let startPhase: CGFloat = bright ? -80 : -60

            Text(label)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(baseColor.opacity(baseOpacity))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(midOpacity), location: bright ? 0.35 : 0.4),
                            .init(color: .white.opacity(peakOpacity), location: 0.5),
                            .init(color: .white.opacity(midOpacity), location: bright ? 0.65 : 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: phase)
                    .mask(
                        Text(label)
                            .font(.system(size: fontSize, design: .monospaced))
                    )
                )
                .onAppear {
                    phase = startPhase
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                        phase = endPhase
                    }
                }
                .onDisappear { phase = startPhase }
        }
    }
}
