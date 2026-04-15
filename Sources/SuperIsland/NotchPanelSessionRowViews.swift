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

private struct CompactSessionRenderSignature: Equatable {
    let sessionId: String
    let status: AgentStatus
    let projectName: String
    let sessionLabel: String?
    let displaySessionId: String
    let previewText: String?
    let sourceLabel: String
    let terminalName: String?
    let interrupted: Bool
    let isYoloMode: Bool
    let needsCompletionReview: Bool
    let ageText: String
}

struct CompactSessionRow: View, Equatable {
    var appState: AppState
    let sessionId: String
    let session: SessionSnapshot
    let isSelected: Bool
    let needsCompletionReview: Bool
    @State private var hovering = false
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines

    static func == (lhs: CompactSessionRow, rhs: CompactSessionRow) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.renderSignature == rhs.renderSignature
    }

    private var renderSignature: CompactSessionRenderSignature {
        CompactSessionRenderSignature(
            sessionId: sessionId,
            status: session.status,
            projectName: session.projectDisplayName,
            sessionLabel: session.sessionLabel,
            displaySessionId: session.displaySessionId(sessionId: sessionId),
            previewText: previewText,
            sourceLabel: session.sourceLabel,
            terminalName: session.terminalName,
            interrupted: session.interrupted,
            isYoloMode: session.isYoloMode == true,
            needsCompletionReview: needsCompletionReview,
            ageText: timeAgoText(session.lastActivity)
        )
    }

    private var previewLineLimit: Int? {
        guard aiMessageLines > 0 else { return nil }
        return needsCompletionReview ? max(aiMessageLines, 5) : max(aiMessageLines, 3)
    }

    var body: some View {
        HStack(spacing: 10) {
            CompactSessionMascotBadge(
                source: session.source,
                status: session.status,
                isSelected: isSelected,
                isHovered: hovering,
                animated: mascotAnimated
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(session.projectDisplayName)
                            .font(.system(size: 12.8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)

                        if let label = session.sessionLabel {
                            Text("#\(label)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.56))
                                .lineLimit(1)
                        }

                        Text("#\(shortSessionId(session.displaySessionId(sessionId: sessionId)))")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.34))
                            .fixedSize()
                    }

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

                HStack(alignment: .top, spacing: 6) {
                    if let previewText, !previewText.isEmpty {
                        Text(previewText)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(isSelected ? 0.72 : 0.54))
                            .lineLimit(previewLineLimit)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    } else if session.status != .idle {
                        Text("thinking")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                self.hovering = hovering
            }
        }
        .onTapGesture {
            appState.jumpToSession(sessionId)
        }
    }

    private var previewText: String? {
        if session.status != .idle, let tool = session.currentTool {
            let value = (session.toolDescription ?? tool).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? tool : value
        }

        if let assistant = session.lastAssistantMessage {
            let cleaned = condensedMessagePreview(stripDirectives(assistant))
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let prompt = session.lastUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return prompt
        }

        if let lastMessage = session.recentMessages.last?.text {
            let cleaned = condensedMessagePreview(stripDirectives(lastMessage))
            return cleaned.isEmpty ? nil : cleaned
        }

        return nil
    }

    private var titleColor: Color {
        if isSelected {
            return .white.opacity(0.92)
        }
        if hovering {
            return .white.opacity(0.82)
        }
        switch session.status {
        case .processing, .running:
            return Color(red: 0.3, green: 0.85, blue: 0.4).opacity(0.92)
        case .waitingApproval, .waitingQuestion:
            return Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.92)
        case .idle:
            return .white.opacity(0.74)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.11)
        }
        if needsCompletionReview {
            return hovering ? completionReviewColor.opacity(0.22) : completionReviewColor.opacity(0.16)
        }
        if hovering {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.035)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.white.opacity(0.12)
        }
        if needsCompletionReview {
            return completionReviewColor.opacity(hovering ? 0.42 : 0.30)
        }
        if hovering {
            return Color.white.opacity(0.08)
        }
        return Color.clear
    }

    private var completionReviewColor: Color {
        Color(red: 0.32, green: 0.74, blue: 1.0)
    }

    private var mascotAnimated: Bool {
        session.status != .idle || isSelected || hovering
    }
}

private struct CompactSessionMascotBadge: View {
    let source: String
    let status: AgentStatus
    let isSelected: Bool
    let isHovered: Bool
    let animated: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(chipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(chipBorder, lineWidth: 1)
                )
                .frame(width: 26, height: 26)

            MascotView(source: source, status: status, size: 18, animated: animated)
                .frame(width: 22, height: 22)

            Circle()
                .fill(primaryTint)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.38), lineWidth: 0.8)
                )
                .offset(x: 1, y: 1)
        }
        .frame(width: 26, height: 26)
    }

    private var chipFill: Color {
        if isSelected {
            return Color.white.opacity(0.09)
        }
        if isHovered {
            return Color.white.opacity(0.06)
        }
        return Color.white.opacity(0.03)
    }

    private var chipBorder: Color {
        if isSelected {
            return Color.white.opacity(0.12)
        }
        if isHovered {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.04)
    }

    private var primaryTint: Color {
        switch status {
        case .processing, .running:
            return Color(red: 0.3, green: 0.85, blue: 0.4).opacity(isSelected || isHovered ? 1 : 0.8)
        case .waitingApproval, .waitingQuestion:
            return Color(red: 1.0, green: 0.6, blue: 0.2).opacity(isSelected || isHovered ? 1 : 0.82)
        case .idle:
            return Color.white.opacity(isSelected || isHovered ? 0.5 : 0.26)
        }
    }
}
