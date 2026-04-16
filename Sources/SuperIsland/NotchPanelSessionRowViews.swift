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
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails

    private var fontSize: CGFloat { CGFloat(contentFontSize) }

    private var chrome: SessionRowChromeStyle {
        SessionRowChrome.style(
            status: session.status,
            interrupted: session.interrupted,
            isSelected: isSelected,
            isHovered: hovering,
            needsCompletionReview: needsCompletionReview
        )
    }

    /// Full cards should still be compact in the list: one user line, one answer/status line.
    private var previewLines: SessionListPreviewLines {
        session.fixedListPreviewLines
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rowPrimaryContent
                .allowsHitTesting(false)

            SessionTrailingMetaColumn(
                session: session,
                needsCompletionReview: needsCompletionReview,
                completionReviewColor: SessionRowChrome.reviewTint
            ) {
                appState.jumpToSession(sessionId)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(chrome.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(chrome.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(chrome.rail.opacity(chrome.railOpacity))
                .frame(width: 2)
                .padding(.vertical, 12)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            // Row-wide taps should enter detail, while the trailing jump button keeps its own explicit action.
            appState.panelCoordinator.handleRowTap(sessionId: sessionId)
        }
        .onHover { hovering in
            withAnimation(NotchAnimation.micro) { self.hovering = hovering }
        }
    }

    private var mascotAnimated: Bool {
        session.status != .idle || isSelected || hovering
    }

    /// Keep the passive row content separate so the trailing buttons can stay independently tappable.
    private var rowPrimaryContent: some View {
        HStack(alignment: .top, spacing: 8) {
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
                SessionIdentityLine(
                    session: session,
                    sessionId: sessionId,
                    projectFontSize: fontSize + 2,
                    projectColor: chrome.title,
                    sessionFontSize: fontSize,
                    sessionColor: chrome.secondaryText,
                    dividerColor: .white.opacity(0.28)
                )

                VStack(alignment: .leading, spacing: 3) {
                    if let userText = previewLines.userText, !userText.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text(">")
                                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                            Text(ChatMessageTextFormatter.literalText(userText))
                                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                .foregroundStyle(chrome.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if let assistantText = previewLines.assistantText, !assistantText.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text("$")
                                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            Text(ChatMessageTextFormatter.inlineMarkdown(condensedMessagePreview(stripDirectives(assistantText))))
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(chrome.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            TypingIndicator(
                                fontSize: fontSize,
                                label: "思考中",
                                color: chrome.secondaryText
                            )
                        }
                    }
                }
                .padding(.leading, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
