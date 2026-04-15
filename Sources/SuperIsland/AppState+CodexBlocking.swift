import Foundation
import SwiftUI
import SuperIslandCore

extension AppState {
    func handleCodexPermissionNotification(_ note: Notification) {
        guard let interaction = CodexInteractionCoordinator.permissionInteraction(
            from: note,
            requestRefresh: { [weak self] in
                self?.requestCodexRefresh(minimumInterval: 0)
            }
        ) else { return }

        enqueueCodexPermissionRequest(interaction.request, event: interaction.event, sessionId: interaction.threadId)
    }

    func handleCodexQuestionNotification(_ note: Notification) {
        guard let interaction = CodexInteractionCoordinator.questionInteraction(
            from: note,
            requestRefresh: { [weak self] in
                self?.requestCodexRefresh(minimumInterval: 0)
            }
        ) else { return }

        enqueueCodexQuestionRequest(interaction.request, event: interaction.event, sessionId: interaction.threadId)
    }

    func handleCodexRefreshNotification(_ note: Notification) {
        let threadId = CodexInteractionCoordinator.refreshThreadId(from: note)
        guard let threadId else {
            requestCodexRefresh(minimumInterval: 0)
            return
        }
        let trackedSessionId = trackedSessionId(forCodexThreadId: threadId, cwd: nil) ?? threadId
        if sessions[trackedSessionId] == nil {
            sessions[trackedSessionId] = SessionSnapshot()
            sessions[trackedSessionId]?.source = "codex"
            sessions[trackedSessionId]?.providerSessionId = threadId
        }
        requestCodexRefresh(minimumInterval: 0)
    }

    func enqueueCodexPermissionRequest(_ request: PermissionRequest, event: HookEvent, sessionId: String) {
        prepareCodexBlockingSession(
            sessionId: sessionId,
            event: event,
            status: .waitingApproval
        ) { session in
            session.currentTool = event.toolName
            session.toolDescription = event.toolDescription
        }
        drainQuestions(forSession: sessionId)
        drainPermissions(forSession: sessionId)
        permissionQueue.append(request)

        activeSessionId = sessionId
        presentSurface(.approvalCard(sessionId: sessionId), reason: .notification)
        SoundManager.shared.handleEvent("PermissionRequest")
        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
    }

    func enqueueCodexQuestionRequest(_ request: QuestionRequest, event: HookEvent, sessionId: String) {
        prepareCodexBlockingSession(
            sessionId: sessionId,
            event: event,
            status: .waitingQuestion
        )
        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)
        questionQueue.append(request)

        activeSessionId = sessionId
        presentSurface(.questionCard(sessionId: sessionId), reason: .notification, animation: NotchAnimation.open)
        SoundManager.shared.handleEvent("PermissionRequest")
        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
    }

    func prepareCodexBlockingSession(
        sessionId: String,
        event: HookEvent,
        status: AgentStatus,
        configure: (inout SessionSnapshot) -> Void = { _ in }
    ) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }

        var session = sessions[sessionId] ?? SessionSnapshot()
        session.source = "codex"
        session.providerSessionId = sessionId
        session.cwd = session.cwd ?? nonEmpty(event.rawJSON["cwd"] as? String)
        session.status = status
        session.lastActivity = Date()
        configure(&session)
        sessions[sessionId] = session
        scheduleTerminalIndexPersist(sessionId: sessionId)
    }
}
