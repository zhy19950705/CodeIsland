import SwiftUI

struct NotchPrimaryBarView: View {
    var appState: AppState
    let showBar: Bool
    let showIdleIndicator: Bool
    let shouldShowExpanded: Bool
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let idleHovered: Bool
    let showToolStatus: Bool

    var body: some View {
        if showBar {
            HStack(spacing: 0) {
                CompactLeftWing(
                    appState: appState,
                    expanded: shouldShowExpanded,
                    mascotSize: mascotSize,
                    hasNotch: hasNotch,
                    showToolStatus: showToolStatus
                )
                if hasNotch && !shouldShowExpanded {
                    Spacer(minLength: notchW)
                } else if !shouldShowExpanded && showToolStatus {
                    CompactToolStatus(appState: appState)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
                CompactRightWing(appState: appState, expanded: shouldShowExpanded, hasNotch: hasNotch)
            }
            .frame(height: notchHeight)
        } else if showIdleIndicator {
            IdleIndicatorBar(
                mascotSize: mascotSize,
                compactWingWidth: compactWingWidth,
                notchW: notchW,
                notchHeight: notchHeight,
                hasNotch: hasNotch,
                hovered: idleHovered
            )
        } else {
            Spacer()
                .frame(height: notchHeight)
        }
    }
}

struct NotchExpandedContentView: View {
    var appState: AppState

    var body: some View {
        Line()
            .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
            .frame(height: 0.5)
            .padding(.horizontal, 12)

        switch appState.surface {
        case .approvalCard(let sessionId):
            if let pending = appState.pendingPermission {
                ApprovalBar(
                    tool: pending.event.toolName ?? "Unknown",
                    toolInput: pending.event.toolInput,
                    session: appState.sessions[sessionId],
                    queuePosition: 1,
                    queueTotal: appState.permissionQueue.count,
                    onAllow: { appState.approvePermission(always: false) },
                    onAlwaysAllow: { appState.approvePermission(always: true) },
                    onDeny: { appState.denyPermission() },
                    onJump: { appState.jumpToSession(sessionId) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if let preview = appState.previewApprovalPayload {
                ApprovalBar(
                    tool: preview.tool,
                    toolInput: preview.toolInput,
                    queuePosition: 1,
                    queueTotal: 1,
                    onAllow: {},
                    onAlwaysAllow: {},
                    onDeny: {}
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        case .questionCard(let sessionId):
            let session = appState.sessions[sessionId]
            if let question = appState.pendingQuestion {
                QuestionBar(
                    question: question.question.question,
                    options: question.question.options,
                    descriptions: question.question.descriptions,
                    sessionSource: session?.source,
                    sessionContext: session?.cwd,
                    session: session,
                    queuePosition: 1,
                    queueTotal: appState.questionQueue.count,
                    onAnswer: { appState.answerQuestion($0) },
                    onSkip: { appState.skipQuestion() },
                    onJump: { appState.jumpToSession(sessionId) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if let preview = appState.previewQuestionPayload {
                QuestionBar(
                    question: preview.question,
                    options: preview.options,
                    descriptions: preview.descriptions,
                    sessionSource: session?.source,
                    sessionContext: session?.cwd,
                    queuePosition: 1,
                    queueTotal: 1,
                    onAnswer: { _ in },
                    onSkip: {}
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        case .completionCard:
            SessionListView(appState: appState, onlySessionId: appState.justCompletedSessionId)
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .sessionList:
            SessionListView(appState: appState, onlySessionId: nil)
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .collapsed:
            EmptyView()
        }
    }
}
