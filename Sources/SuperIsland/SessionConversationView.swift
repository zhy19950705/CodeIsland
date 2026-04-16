import SwiftUI
import SuperIslandCore

enum SessionConversationViewStyle: Equatable {
    case inline
    case detail
}

/// Inline conversation detail shown under the selected session card.
struct SessionConversationView: View {
    let sessionId: String
    let session: SessionSnapshot
    var style: SessionConversationViewStyle = .inline

    @ObservedObject private var historyManager = ChatHistoryManager.shared

    /// Use an explicit initializer so call sites stay stable even with property-wrapper stored properties.
    init(
        sessionId: String,
        session: SessionSnapshot,
        style: SessionConversationViewStyle = .inline
    ) {
        self.sessionId = sessionId
        self.session = session
        self.style = style
    }

    var body: some View {
        let state = historyManager.state(for: sessionId)

        VStack(alignment: .leading, spacing: 10) {
            if style == .inline {
                ConversationSourceHeader(sourcePath: state.sourcePath)
            }

            SessionConversationBody(sessionId: sessionId, session: session, state: state, style: style)
        }
        .padding(.top, style == .inline ? 6 : 0)
        // Detail mode should stay width-stable without forcing the whole popup to full height.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: loadKey) {
            await historyManager.load(sessionId: sessionId, session: session)
        }
    }

    /// Detail refreshes when the active transcript source or last activity changes.
    private var loadKey: String {
        let sourcePath = session.claudeTranscriptPath ?? session.providerSessionId ?? session.cwd ?? sessionId
        return "\(sessionId)-\(sourcePath)-\(session.lastActivity.timeIntervalSince1970)"
    }
}

/// Shared header keeps inline and detail modes visually aligned without duplicating transcript metadata code.
private struct ConversationSourceHeader: View {
    let sourcePath: String?
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.56))
            Text(l10n["session_detail_conversation"])
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
            if let sourcePath, !sourcePath.isEmpty {
                Text(URL(fileURLWithPath: sourcePath).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            }
        }
    }
}

/// Shared body lets the inline preview and full detail surface reuse the same parsed timeline rendering.
private struct SessionConversationBody: View {
    let sessionId: String
    let session: SessionSnapshot
    let state: SessionConversationState
    let style: SessionConversationViewStyle
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if state.isLoading && state.items.isEmpty {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.45))
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if style == .detail {
            DetailConversationTimeline(sessionId: sessionId, session: session, state: state)
        } else if let errorText = state.errorText, state.items.isEmpty {
            Text(errorText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.vertical, 6)
        } else if state.items.isEmpty {
            Text(l10n["session_detail_no_history"])
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.vertical, 6)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(state.items) { item in
                        ConversationHistoryRow(item: item, linkContext: linkContext)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: style == .inline ? 280 : nil)
            .padding(.horizontal, style == .detail ? 14 : 0)
            .padding(.bottom, style == .detail ? 10 : 0)
        }
    }

    /// A shared link context keeps relative markdown links and tool file previews aligned with the active workspace.
    private var linkContext: EditorLinkContext {
        EditorLinkContext(sessionId: sessionId, session: session)
    }
}

private struct ConversationHistoryRow: View {
    let item: ConversationHistoryItem
    let linkContext: EditorLinkContext

    var body: some View {
        switch item.kind {
        case .user(let text):
            ConversationBubble(prefix: ">", prefixColor: Color(red: 0.34, green: 0.86, blue: 0.44)) {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        case .assistant(let text):
            ConversationBubble(prefix: "$", prefixColor: Color(red: 0.92, green: 0.55, blue: 0.34)) {
                MarkdownText(text, color: .white.opacity(0.86), fontSize: 12, linkContext: linkContext)
                    .textSelection(.enabled)
            }
        case .thinking(let text):
            ConversationBubble(prefix: "~", prefixColor: .white.opacity(0.42)) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
                    .italic()
                    .textSelection(.enabled)
            }
        case .interrupted(let text):
            ConversationBubble(prefix: "!", prefixColor: .orange.opacity(0.86)) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.82))
                    .textSelection(.enabled)
            }
        case .toolCall(let tool):
            ToolConversationRow(tool: tool, linkContext: linkContext)
        }
    }
}

private struct ConversationBubble<Content: View>: View {
    let prefix: String
    let prefixColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(prefixColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ToolConversationRow: View {
    let tool: ConversationToolCall
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                    .foregroundStyle(.cyan.opacity(0.82))
                Text(tool.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.84))
                Text(tool.status.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.16)))
                Spacer(minLength: 0)
            }

            if !tool.inputPreview.isEmpty {
                Text(tool.inputPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }

            ToolResultContent(tool: tool, linkContext: linkContext)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
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
