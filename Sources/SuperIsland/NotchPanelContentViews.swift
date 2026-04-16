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
            .contentShape(Rectangle())
            .onTapGesture {
                guard !shouldShowExpanded else { return }
                // 给收起态增加显式点击展开兜底，避免悬停监听在启动阶段或系统权限未就绪时
                // 失效后，用户完全无法展开会话列表。
                appState.panelCoordinator.openSessionList(reason: .click)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Line()
                .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            ZStack(alignment: .top) {
                surfaceContent
                    .id(appState.surface.transitionIdentity)
                    .transition(reduceMotion ? .opacity : Self.transition(for: appState.surface))
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .animation(reduceMotion ? nil : NotchAnimation.surfaceSwap, value: appState.presentationState.content)
    }

    /// Keep the switch body separate from the transition container so each surface
    /// can own a stable identity while the wrapper controls the cross-surface motion.
    @ViewBuilder
    private var surfaceContent: some View {
        switch appState.surface {
        case .sessionDetail(let sessionId):
            if let session = appState.sessions[sessionId] {
                SessionDetailView(appState: appState, sessionId: sessionId, session: session)
            } else {
                SessionListView(appState: appState, onlySessionId: nil)
            }
        case .completionCard(let sessionId):
            if let session = appState.sessions[sessionId] {
                SessionDetailView(appState: appState, sessionId: sessionId, session: session)
            } else {
                SessionListView(appState: appState, onlySessionId: nil)
            }
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
            }
        case .sessionList:
            SessionListView(appState: appState, onlySessionId: nil)
        case .collapsed:
            EmptyView()
        }
    }

    /// Motion stays lightweight and profile-driven so the content area feels more
    /// intentional without forcing heavyweight matched-geometry machinery.
    private static func transition(for surface: IslandSurface) -> AnyTransition {
        switch surface.motionProfile {
        case .list:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
            )
        case .detail:
            return .asymmetric(
                insertion: .opacity
                    .combined(with: .move(edge: .trailing))
                    .combined(with: .scale(scale: 0.985, anchor: .topTrailing)),
                removal: .opacity
                    .combined(with: .move(edge: .leading))
                    .combined(with: .scale(scale: 0.985, anchor: .topLeading))
            )
        case .blockingCard:
            return .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
        case .completion:
            return .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.985, anchor: .top))
        case .collapsed:
            return .opacity
        }
    }
}
