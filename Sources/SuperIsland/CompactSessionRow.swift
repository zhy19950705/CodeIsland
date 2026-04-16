import SwiftUI
import SuperIslandCore

// Keep compact session row rendering in a separate file so the main session card file stays within a manageable size.
private struct CompactSessionRenderSignature: Equatable {
    let sessionId: String
    let status: AgentStatus
    let projectName: String
    let sessionLabel: String?
    let displaySessionId: String
    let previewUserText: String?
    let previewAssistantText: String?
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

    static func == (lhs: CompactSessionRow, rhs: CompactSessionRow) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.renderSignature == rhs.renderSignature
    }

    private var chrome: SessionRowChromeStyle {
        SessionRowChrome.style(
            status: session.status,
            interrupted: session.interrupted,
            isSelected: isSelected,
            isHovered: hovering,
            needsCompletionReview: needsCompletionReview
        )
    }

    private var renderSignature: CompactSessionRenderSignature {
        CompactSessionRenderSignature(
            sessionId: sessionId,
            status: session.status,
            projectName: session.projectDisplayName,
            sessionLabel: session.sessionLabel,
            displaySessionId: session.displaySessionId(sessionId: sessionId),
            previewUserText: previewLines.userText,
            previewAssistantText: previewLines.assistantText,
            sourceLabel: session.sourceLabel,
            terminalName: session.terminalName,
            interrupted: session.interrupted,
            isYoloMode: session.isYoloMode == true,
            needsCompletionReview: needsCompletionReview,
            ageText: timeAgoText(session.lastActivity)
        )
    }

    /// Compact rows follow the same one-question one-answer rhythm as full cards.
    private var previewLines: SessionListPreviewLines {
        session.fixedListPreviewLines
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            rowPrimaryContent
                .allowsHitTesting(false)

            SessionTrailingMetaColumn(
                session: session,
                needsCompletionReview: needsCompletionReview,
                completionReviewColor: SessionRowChrome.reviewTint
            ) {
                appState.jumpToSession(sessionId)
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(chrome.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(chrome.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(chrome.rail.opacity(chrome.railOpacity))
                .frame(width: 2)
                .padding(.vertical, 9)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            // Compact rows share the same row-wide detail affordance as full cards.
            appState.panelCoordinator.handleRowTap(sessionId: sessionId)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                self.hovering = hovering
            }
        }
    }

    private var mascotAnimated: Bool {
        session.status != .idle || isSelected || hovering
    }

    /// Compact-row text and mascot should visually sit on top of the full-card hit area without becoming nested controls.
    private var rowPrimaryContent: some View {
        HStack(alignment: .top, spacing: 10) {
            CompactSessionMascotBadge(
                source: session.source,
                status: session.status,
                isSelected: isSelected,
                isHovered: hovering,
                animated: mascotAnimated
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                SessionIdentityLine(
                    session: session,
                    sessionId: sessionId,
                    projectFontSize: 12.8,
                    projectColor: chrome.title,
                    sessionFontSize: 10.5,
                    sessionColor: chrome.secondaryText,
                    dividerColor: .white.opacity(0.28)
                )

                VStack(alignment: .leading, spacing: 2) {
                    if let userText = previewLines.userText, !userText.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text(">")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                            Text(ChatMessageTextFormatter.literalText(userText))
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(chrome.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if let assistantText = previewLines.assistantText, !assistantText.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text("$")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            Text(ChatMessageTextFormatter.inlineMarkdown(condensedMessagePreview(stripDirectives(assistantText))))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(chrome.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            Text("$")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            TypingIndicator(
                                fontSize: 10.5,
                                label: "thinking",
                                color: chrome.secondaryText
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        let style = SessionRowChrome.style(
            status: status,
            interrupted: false,
            isSelected: isSelected,
            isHovered: isHovered,
            needsCompletionReview: false
        )
        return style.symbolFill
    }

    private var chipBorder: Color {
        let style = SessionRowChrome.style(
            status: status,
            interrupted: false,
            isSelected: isSelected,
            isHovered: isHovered,
            needsCompletionReview: false
        )
        return style.symbolBorder
    }

    private var primaryTint: Color {
        let accent = SessionRowChrome.accent(
            status: status,
            interrupted: false,
            needsCompletionReview: false
        )
        if status == .idle {
            return accent.opacity(isSelected || isHovered ? 0.52 : 0.28)
        }
        return accent.opacity(isSelected || isHovered ? 1 : 0.84)
    }
}
