import SwiftUI
import SuperIslandCore

// NotchPanelSessionRowViews keeps the heavy card and compact-row rendering separate from SessionListView's grouping logic.
struct SessionCard: View {
    var appState: AppState
    let sessionId: String
    let session: SessionSnapshot
    var isCompletion: Bool = false
    var isSelected: Bool = false
    var needsCompletionReview: Bool = false
    @State private var hovering = false
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails

    private var fontSize: CGFloat { CGFloat(contentFontSize) }

    private var previewLineLimit: Int? {
        guard aiMessageLines > 0 else { return nil }
        return isCompletion ? max(aiMessageLines, 5) : max(aiMessageLines, 3)
    }

    private var visibleMessages: [ChatMessage] {
        session.latestConversationPreviewMessages
    }

    private var statusNameColor: Color {
        if session.status == .idle && session.interrupted {
            return Color(red: 1.0, green: 0.45, blue: 0.35)
        }
        switch session.status {
        case .processing, .running:
            return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval, .waitingQuestion:
            return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .idle:
            return .white
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 3) {
                MascotView(source: session.source, status: session.status, size: 32, animated: mascotAnimated)
                if showAgentDetails && !session.subagents.isEmpty {
                    let sorted = session.subagents.values.sorted { $0.startTime < $1.startTime }
                    let rows = stride(from: 0, to: sorted.count, by: 4).map {
                        Array(sorted[$0..<min($0 + 4, sorted.count)])
                    }
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 1) {
                                ForEach(row, id: \.agentId) { sub in
                                    MiniAgentIcon(active: sub.status != .idle, size: 8)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    SessionIdentityLine(
                        session: session,
                        sessionId: sessionId,
                        projectFontSize: fontSize + 2,
                        projectColor: statusNameColor,
                        sessionFontSize: fontSize,
                        sessionColor: .white.opacity(0.76),
                        dividerColor: .white.opacity(0.28)
                    )
                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        if session.interrupted {
                            SessionTag("INT", color: Color(red: 1.0, green: 0.6, blue: 0.2))
                        }
                        if session.isYoloMode == true {
                            SessionTag("YOLO", color: Color(red: 1.0, green: 0.35, blue: 0.35))
                        }
                        if needsCompletionReview {
                            SessionTag(L10n.shared["completion_pending_review"], color: completionReviewColor)
                        }
                        SessionTag(timeAgoText(session.lastActivity))
                        TerminalJumpAccessory(session: session, isHovered: hovering)
                    }
                }

                if !visibleMessages.isEmpty || session.status != .idle {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(visibleMessages) { message in
                            if message.isUser {
                                HStack(alignment: .top, spacing: 4) {
                                    Text(">")
                                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                                    Text(ChatMessageTextFormatter.literalText(message.text))
                                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(previewLineLimit)
                                        .truncationMode(.tail)
                                }
                            } else {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("$")
                                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                                    Text(ChatMessageTextFormatter.inlineMarkdown(condensedMessagePreview(stripDirectives(message.text))))
                                        .font(.system(size: fontSize, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(previewLineLimit)
                                        .truncationMode(.tail)
                                }
                            }
                        }

                        if session.status != .idle {
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                                if let tool = session.currentTool {
                                    Text(session.toolDescription ?? tool)
                                        .font(.system(size: fontSize, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                } else {
                                    TypingIndicator(fontSize: fontSize, label: "thinking")
                                }
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchAnimation.micro) { self.hovering = hovering }
        }
        .onTapGesture {
            appState.jumpToSession(sessionId)
        }
    }

    private var cardBackgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.12)
        }
        if needsCompletionReview {
            return hovering ? completionReviewColor.opacity(0.24) : completionReviewColor.opacity(0.18)
        }
        return hovering ? Color.white.opacity(0.10) : Color.white.opacity(0.05)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return Color.white.opacity(0.14)
        }
        if needsCompletionReview {
            return completionReviewColor.opacity(hovering ? 0.44 : 0.32)
        }
        return .clear
    }

    private var completionReviewColor: Color {
        Color(red: 0.32, green: 0.74, blue: 1.0)
    }

    private var mascotAnimated: Bool {
        session.status != .idle || isSelected || hovering
    }
}
