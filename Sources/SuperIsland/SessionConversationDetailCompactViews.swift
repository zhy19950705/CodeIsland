import SwiftUI

/// Claude detail follows MioIsland's denser tool summary view so a long transcript
/// does not render every tool result inline by default.
struct DetailToolConversationRow: View {
    let tool: ConversationToolCall
    let linkContext: EditorLinkContext
    let compactByDefault: Bool

    @State private var isExpanded = false

    private var hasResult: Bool {
        tool.resultText != nil || tool.structuredResult != nil
    }

    private var canExpand: Bool {
        tool.name != "Task" && tool.name != "Edit" && hasResult
    }

    private var shouldShowExpandedContent: Bool {
        if compactByDefault {
            return isExpanded && tool.status != .running && tool.status != .waitingForApproval
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                    .foregroundStyle(.cyan.opacity(0.82))
                Text(tool.name)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                Text(tool.status.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.16)))

                if compactByDefault {
                    Text(tool.fallbackDisplayText ?? tool.status.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                if compactByDefault && canExpand && tool.status != .running && tool.status != .waitingForApproval {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }

            if !compactByDefault && !tool.inputPreview.isEmpty {
                Text(tool.inputPreview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shouldShowExpandedContent {
                ToolResultContent(tool: tool, linkContext: linkContext)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard compactByDefault, canExpand else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .running:
            return .orange.opacity(0.9)
        case .waitingForApproval:
            return .yellow.opacity(0.9)
        case .success:
            return .green.opacity(0.9)
        case .error:
            return .red.opacity(0.9)
        case .interrupted:
            return .orange.opacity(0.9)
        }
    }
}

/// Thinking traces are useful, but Claude detail should not dump the full chain-of-thought
/// inline by default because that makes the panel feel like a raw log viewer.
struct DetailThinkingRow: View {
    let text: String
    let compactByDefault: Bool

    @State private var isExpanded = false

    private var canExpand: Bool {
        compactByDefault && text.count > 80
    }

    private var displayText: String {
        guard compactByDefault, !isExpanded, canExpand else { return text }
        return String(text.prefix(80)) + "..."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 3)
            Text(displayText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
                .italic()
                .textSelection(.enabled)
                .lineLimit(compactByDefault && !isExpanded ? 1 : nil)
            Spacer(minLength: 56)

            if canExpand {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.26))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        }
    }
}
