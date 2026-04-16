import SwiftUI

struct MenuBarPopoverView: View {
    enum Mode: Equatable {
        case contextual
        case sessionListOnly
    }

    var appState: AppState
    var mode: Mode = .contextual
    @ObservedObject private var historyManager = ChatHistoryManager.shared

    private var visibleSurface: IslandSurface {
        if mode == .sessionListOnly {
            return .sessionList
        }

        if let pendingPermission = appState.pendingPermission,
           let sessionId = pendingPermission.event.sessionId {
            return .approvalCard(sessionId: sessionId)
        }

        if let pendingQuestion = appState.pendingQuestion,
           let sessionId = pendingQuestion.event.sessionId {
            return .questionCard(sessionId: sessionId)
        }

        switch appState.surface {
        case .collapsed:
            return .sessionList
        default:
            return appState.surface
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.08))
            content
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: 430, height: popoverHeight, alignment: .top)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    /// Dedicated transcript detail should follow the same content-aware height budget as the notch panel.
    private var popoverHeight: CGFloat {
        switch visibleSurface {
        case .sessionDetail(let sessionId), .completionCard(let sessionId):
            return SessionDetailLayoutMetrics.estimatedPopoverHeight(
                session: appState.sessions[sessionId],
                conversationState: historyManager.state(for: sessionId)
            )
        case .approvalCard, .questionCard, .collapsed, .sessionList:
            return 560
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let icon = cliIcon(source: headerSource, size: 16) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text("SuperIsland")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Reuse the full notch control cluster in the menu bar so sound, settings, and quit stay visually aligned.
                NotchControlButtonGroup(showsSoundToggle: true, trailingAction: .quitApp)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(headerSubtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    private var usageProviders: [UsageProviderSnapshot] {
        guard let source = UsageProviderSource(rawValue: headerSource) else { return [] }
        return appState.usageSnapshot.providers.filter { $0.source == source }
    }

    @ViewBuilder
    private var content: some View {
        switch visibleSurface {
        case .sessionDetail(let sessionId):
            if let session = appState.sessions[sessionId] {
                SessionDetailView(appState: appState, sessionId: sessionId, session: session)
                    .padding(.top, 8)
            } else {
                fallbackSessionList
            }

        case .approvalCard:
            if let pendingPermission = appState.pendingPermission {
                let sessionId = pendingPermission.event.sessionId ?? appState.activeSessionId
                ApprovalBar(
                    tool: pendingPermission.event.toolName ?? "Unknown",
                    toolInput: pendingPermission.event.toolInput,
                    session: sessionId.flatMap { appState.sessions[$0] },
                    queuePosition: 1,
                    queueTotal: appState.permissionQueue.count,
                    onAllow: { appState.approvePermission(always: false) },
                    onAlwaysAllow: { appState.approvePermission(always: true) },
                    onDeny: { appState.denyPermission() },
                    onJump: {
                        if let sessionId {
                            appState.jumpToSession(sessionId)
                        }
                    }
                )
                .padding(.top, 12)
            } else {
                fallbackSessionList
            }

        case .questionCard(let sessionId):
            if let pendingQuestion = appState.pendingQuestion {
                QuestionBar(
                    question: pendingQuestion.question.question,
                    options: pendingQuestion.question.options,
                    descriptions: pendingQuestion.question.descriptions,
                    sessionSource: appState.sessions[sessionId]?.source,
                    sessionContext: appState.sessions[sessionId]?.cwd,
                    session: appState.sessions[sessionId],
                    queuePosition: 1,
                    queueTotal: appState.questionQueue.count,
                    onAnswer: { appState.answerQuestion($0) },
                    onSkip: { appState.skipQuestion() },
                    onJump: { appState.jumpToSession(sessionId) }
                )
                .padding(.top, 12)
            } else {
                fallbackSessionList
            }

        case .completionCard(let sessionId):
            if let session = appState.sessions[sessionId] {
                SessionDetailView(appState: appState, sessionId: sessionId, session: session)
                    .padding(.top, 8)
            } else {
                fallbackSessionList
            }

        case .collapsed, .sessionList:
            fallbackSessionList
        }
    }

    private var fallbackSessionList: some View {
        SessionListView(appState: appState, onlySessionId: nil, presentation: .menuBar)
    }

    private var headerSubtitle: String {
        let sessionCount = appState.sessions.count
        if let activeSessionId = appState.activeSessionId,
           let session = appState.sessions[activeSessionId] {
            return "\(session.sourceLabel) · \(session.projectDisplayName) · \(sessionCount) \(AppText.shared["n_sessions"])"
        }
        return "\(sessionCount) \(AppText.shared["n_sessions"])"
    }

    private var headerSource: String {
        if let activeSessionId = appState.activeSessionId,
           let session = appState.sessions[activeSessionId] {
            return session.source
        }
        return appState.primarySource
    }
}
