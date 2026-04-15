import SwiftUI
import Foundation
import SuperIslandCore

// NotchPanelSessionListSupport groups shared list accessories and text helpers so the main list file only owns layout orchestration.
struct CodexComposerBar: View {
    let projectName: String
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = cliIcon(source: "codex", size: 12) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(projectName)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
            }

            HStack(spacing: 8) {
                Text(">")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                TextField(L10n.shared["type_message"], text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                Button(action: onSubmit) {
                    Text(L10n.shared["send"])
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.16, green: 0.38, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .onAppear { isFocused = false }
    }
}

struct AutoHeightSessionScrollView<Content: View, ScrollContent: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let scrollContent: () -> ScrollContent
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if contentHeight > maxHeight {
            ScrollView(.vertical) {
                measuredScrollContent
            }
            .scrollIndicators(.automatic)
            .frame(height: maxHeight)
        } else {
            measuredContent
        }
    }

    private var measuredContent: some View {
        content()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SessionListContentHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
            .onPreferenceChange(SessionListContentHeightKey.self) { height in
                if height > 0 {
                    contentHeight = height
                }
            }
    }

    private var measuredScrollContent: some View {
        scrollContent()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SessionListContentHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
            .onPreferenceChange(SessionListContentHeightKey.self) { height in
                if height > 0 {
                    contentHeight = height
                }
            }
    }
}

struct SessionIdentityLine: View {
    let session: SessionSnapshot
    let sessionId: String
    let projectFontSize: CGFloat
    let projectColor: Color
    let sessionFontSize: CGFloat
    let sessionColor: Color
    let dividerColor: Color

    private var displaySessionId: String { session.displaySessionId(sessionId: sessionId) }

    var body: some View {
        HStack(spacing: 4) {
            ProjectNameLabel(
                name: session.projectDisplayName,
                fontSize: projectFontSize,
                color: projectColor
            )
            .layoutPriority(2)

            if let sessionLabel = session.sessionLabel {
                Text("#\(sessionLabel)")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Text("·")
                    .font(.system(size: sessionFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dividerColor)

                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            } else {
                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            }
        }
    }
}

private struct ProjectNameLabel: View {
    let name: String
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct SessionsExpandLink: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @State private var hoverTimer: Timer?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                Text("\(count) \(L10n.shared["n_sessions"])")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.45))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.5 : 0.3))
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.micro) { self.hovering = hovering }
            hoverTimer?.invalidate()
            hoverTimer = nil
            if hovering {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    Task { @MainActor in action() }
                }
            }
        }
    }
}

/// Generate a short session ID with better disambiguation.
func shortSessionId(_ id: String) -> String {
    let clean = id.replacingOccurrences(of: "-", with: "")
    if clean.count >= 8 {
        return String(clean.suffix(4))
    }
    return String(id.prefix(4))
}

/// Strip internal directives (::code-comment{}, ::git-*{}, etc.) from message text
/// so they don't leak into the UI preview.
func stripDirectives(_ text: String) -> String {
    // Use a single forward scan so preview cleanup stays cheap even for long assistant outputs.
    var result: [String] = []
    var inDirective = false
    var braceDepth = 0

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if inDirective {
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth <= 0 {
                inDirective = false
                braceDepth = 0
            }
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("::") && trimmed.contains("{") {
            braceDepth = 0
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth > 0 {
                inDirective = true
            }
            continue
        }

        result.append(String(line))
    }

    return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

func condensedMessagePreview(_ text: String) -> String {
    text
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .reduce(into: [String]()) { result, line in
            if line.isEmpty && (result.last?.isEmpty ?? true) {
                return
            }
            result.append(line)
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func timeAgoText(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 60 {
        return "<1m"
    }
    if seconds < 3600 {
        return "\(seconds / 60)m"
    }
    if seconds < 86_400 {
        return "\(seconds / 3600)h"
    }
    return "\(seconds / 86_400)d"
}
