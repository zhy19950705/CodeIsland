import SwiftUI
import SuperIslandCore

extension AppState {
    func handleEvent(_ event: HookEvent) {
        if let cwd = event.rawJSON["cwd"] as? String,
           SessionFilter.isSyntheticAgentWorktree(cwd) {
            return
        }

        let sessionId = event.sessionId ?? "default"

        if SessionFilter.shouldIgnoreSession(
            source: event.rawJSON["_source"] as? String,
            cwd: event.rawJSON["cwd"] as? String,
            termBundleId: event.rawJSON["_term_bundle"] as? String
        ) {
            if sessions[sessionId] != nil {
                removeSession(sessionId)
            }
            return
        }

        if (event.rawJSON["_source"] as? String) == "codex"
            && sessions[sessionId] == nil
            && event.rawJSON["transcript_path"] is NSNull {
            return
        }

        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }

        let prevStatus = sessions[sessionId]?.status
        let wasWaiting = prevStatus == .waitingApproval || prevStatus == .waitingQuestion

        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: maxHistory)
        let normalizedEventName = EventNormalizer.normalize(event.eventName)

        if normalizedEventName != "Stop" {
            acknowledgePendingCompletionReview(for: sessionId)
        }

        if sessions[sessionId]?.model == nil && !modelReadAttempted.contains(sessionId) {
            modelReadAttempted.insert(sessionId)
            let cwd = sessions[sessionId]?.cwd
            let model = Self.readModelFromTranscript(sessionId: sessionId, cwd: cwd)
            sessions[sessionId]?.model = model
        }

        if wasWaiting {
            let keepWaiting: Set<String> = ["Notification", "SessionStart", "SessionEnd", "PreCompact"]
            if !keepWaiting.contains(normalizedEventName) {
                drainPermissions(forSession: sessionId)
                drainQuestions(forSession: sessionId)
                if sessions[sessionId]?.status == .waitingApproval
                    || sessions[sessionId]?.status == .waitingQuestion {
                    sessions[sessionId]?.status = (normalizedEventName == "Stop") ? .idle : .processing
                    sessions[sessionId]?.currentTool = nil
                    sessions[sessionId]?.toolDescription = nil
                }
                showNextPending()
            }
        }

        if event.rawJSON["_source"] as? String == "cursor",
           sessions[sessionId]?.isYoloMode == nil {
            sessions[sessionId]?.isYoloMode = Self.detectCursorYoloMode()
        }

        if let session = sessions[sessionId],
           !shouldMonitorProcessLifecycle(for: session),
           processMonitors[sessionId] != nil {
            stopMonitor(sessionId)
        }

        for effect in effects {
            executeEffect(effect, sessionId: sessionId)
        }

        if let provider = sessions[sessionId]?.source,
           SessionTitleStore.supports(provider: provider) {
            refreshProviderTitle(for: sessionId)
        }

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        if sessions[sessionId]?.source == "codex" {
            requestCodexRefresh(minimumInterval: 1.0)
        }
        if sessions[sessionId]?.source == "claude" {
            Task { [weak self] in
                await self?.claudeRealtimeTokenMonitor.refreshOnce()
            }
        }

        if sessions[sessionId]?.status == .idle && activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }

        scheduleSave()
        startRotationIfNeeded()
        requestDerivedStateRefresh()
    }

    private func executeEffect(_ effect: SideEffect, sessionId: String) {
        switch effect {
        case .playSound(let eventName):
            SoundManager.shared.handleEvent(eventName)
        case .tryMonitorSession(let sid):
            if processMonitors[sid] == nil {
                tryMonitorSession(sid)
            }
        case .stopMonitor(let sid):
            stopMonitor(sid)
        case .removeSession(let sid):
            removeSession(sid)
        case .enqueueCompletion(let sid):
            enqueueCompletion(sid)
        case .setActiveSession(let sid):
            activeSessionId = sid
        }
    }

    func markPendingCompletionReview(for sessionId: String) {
        guard sessions[sessionId] != nil else { return }
        pendingCompletionReviewSessionIds.insert(sessionId)
    }

    func acknowledgePendingCompletionReview(for sessionId: String) {
        pendingCompletionReviewSessionIds.remove(sessionId)
    }

    @discardableResult
    func handlePermissionRequest(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> UUID {
        let sessionId = prepareBlockingInteraction(
            event,
            status: .waitingApproval,
            drainExisting: { [weak self] sessionId in
                self?.drainQuestions(forSession: sessionId)
            },
            configureSession: { session in
                session.currentTool = event.toolName
                session.toolDescription = event.toolDescription
            }
        )
        let request = PermissionRequest(event: event, continuation: continuation)
        permissionQueue.append(request)

        if permissionQueue.count == 1 {
            activeSessionId = sessionId
            // Blocking cards should restore cleanly after collapse/reopen.
            presentSurface(.approvalCard(sessionId: sessionId), reason: .notification)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
        return request.id
    }

    func approvePermission(always: Bool = false) {
        guard !permissionQueue.isEmpty else { return }
        let pending = permissionQueue.removeFirst()
        if let approveAction = pending.approveAction {
            approveAction(always)
        } else {
            pending.response?.resume(
                returning: BlockingInteractionCoordinator.permissionAllowResponse(
                    event: pending.event,
                    always: always
                )
            )
        }
        let sessionId = pending.event.sessionId ?? "default"
        let nextStatus = BlockingInteractionCoordinator.statusAfterPermissionResolution(
            source: sessions[sessionId]?.source,
            approved: true
        )
        sessions[sessionId]?.status = nextStatus

        showNextPending()
        refreshDerivedState()
    }

    func denyPermission() {
        guard !permissionQueue.isEmpty else { return }
        let pending = permissionQueue.removeFirst()
        if let denyAction = pending.denyAction {
            denyAction()
        } else {
            pending.response?.resume(returning: BlockingInteractionCoordinator.permissionDenyResponse())
        }
        let sessionId = pending.event.sessionId ?? "default"
        let nextStatus = BlockingInteractionCoordinator.statusAfterPermissionResolution(
            source: sessions[sessionId]?.source,
            approved: false
        )
        sessions[sessionId]?.status = nextStatus
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil

        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }

        showNextPending()
        refreshDerivedState()
    }

    @discardableResult
    func handleQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> UUID? {
        let sessionId = prepareBlockingInteraction(
            event,
            status: .waitingQuestion,
            drainExisting: { [weak self] sessionId in
                self?.drainPermissions(forSession: sessionId)
            }
        )
        guard let question = QuestionPayload.from(event: event) else {
            continuation.resume(returning: Data("{}".utf8))
            return nil
        }

        let request = QuestionRequest(event: event, question: question, continuation: continuation)
        questionQueue.append(request)

        if questionQueue.count == 1 {
            activeSessionId = sessionId
            presentSurface(.questionCard(sessionId: sessionId), reason: .notification, animation: NotchAnimation.open)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
        return request.id
    }

    @discardableResult
    func handleAskUserQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> UUID {
        let sessionId = prepareBlockingInteraction(
            event,
            status: .waitingQuestion,
            drainExisting: { [weak self] sessionId in
                self?.drainPermissions(forSession: sessionId)
                self?.drainQuestions(forSession: sessionId)
            }
        )
        let payload = BlockingInteractionCoordinator.askUserQuestionPayload(from: event)

        let request = QuestionRequest(event: event, question: payload, continuation: continuation, isFromPermission: true)
        questionQueue.append(request)

        if questionQueue.count == 1 {
            activeSessionId = sessionId
            presentSurface(.questionCard(sessionId: sessionId), reason: .notification, animation: NotchAnimation.open)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
        return request.id
    }

    func answerQuestion(_ answer: String) {
        guard !questionQueue.isEmpty else { return }
        let pending = questionQueue.removeFirst()
        if let answerAction = pending.answerAction {
            answerAction(answer)
        } else {
            pending.response?.resume(
                returning: BlockingInteractionCoordinator.questionAnswerResponse(
                    question: pending.question,
                    answer: answer,
                    isFromPermission: pending.isFromPermission
                )
            )
        }
        let sessionId = pending.event.sessionId ?? "default"
        sessions[sessionId]?.status = BlockingInteractionCoordinator.statusAfterQuestionResolution()

        showNextPending()
        refreshDerivedState()
    }

    func skipQuestion() {
        guard !questionQueue.isEmpty else { return }
        let pending = questionQueue.removeFirst()
        if let skipAction = pending.skipAction {
            skipAction()
        } else {
            pending.response?.resume(
                returning: BlockingInteractionCoordinator.questionSkipResponse(
                    isFromPermission: pending.isFromPermission
                )
            )
        }
        let sessionId = pending.event.sessionId ?? "default"
        sessions[sessionId]?.status = BlockingInteractionCoordinator.statusAfterQuestionResolution()

        showNextPending()
        refreshDerivedState()
    }

    func drainPermissions(forSession sessionId: String) {
        let denyResponse = BlockingInteractionCoordinator.permissionDenyResponse()
        permissionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            if let denyAction = item.denyAction {
                denyAction()
            } else {
                item.response?.resume(returning: denyResponse)
            }
            return true
        }
    }

    func handlePeerDisconnect(sessionId: String) {
        let hadPending = questionQueue.contains(where: { $0.event.sessionId == sessionId })
            || permissionQueue.contains(where: { $0.event.sessionId == sessionId })
        guard hadPending else { return }

        drainQuestions(forSession: sessionId)
        drainPermissions(forSession: sessionId)
        let currentStatus = sessions[sessionId]?.status
        if currentStatus == .waitingApproval || currentStatus == .waitingQuestion {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }
        showNextPending()
        refreshDerivedState()
    }

    func drainQuestions(forSession sessionId: String) {
        questionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            if let skipAction = item.skipAction {
                skipAction()
            } else {
                item.response?.resume(returning: Data("{}".utf8))
            }
            return true
        }
    }

    private func prepareBlockingInteraction(
        _ event: HookEvent,
        status: AgentStatus,
        drainExisting: (String) -> Void,
        configureSession: (inout SessionSnapshot) -> Void = { _ in }
    ) -> String {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        tryMonitorSession(sessionId)
        acknowledgePendingCompletionReview(for: sessionId)
        drainExisting(sessionId)

        if var session = sessions[sessionId] {
            session.status = status
            session.lastActivity = Date()
            configureSession(&session)
            sessions[sessionId] = session
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }
        return sessionId
    }

    func timeoutPermissionRequest(id: UUID) -> Bool {
        guard let index = permissionQueue.firstIndex(where: { $0.id == id }) else { return false }
        let pending = permissionQueue.remove(at: index)
        if let denyAction = pending.denyAction {
            denyAction()
        } else {
            pending.response?.resume(returning: BlockingInteractionCoordinator.permissionDenyResponse())
        }
        let sessionId = pending.event.sessionId ?? "default"
        let nextStatus = BlockingInteractionCoordinator.statusAfterPermissionResolution(
            source: sessions[sessionId]?.source,
            approved: false
        )
        sessions[sessionId]?.status = nextStatus
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil

        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }

        showNextPending()
        refreshDerivedState()
        return true
    }

    func timeoutQuestionRequest(id: UUID) -> Bool {
        guard let index = questionQueue.firstIndex(where: { $0.id == id }) else { return false }
        let pending = questionQueue.remove(at: index)
        if let skipAction = pending.skipAction {
            skipAction()
        } else {
            pending.response?.resume(
                returning: BlockingInteractionCoordinator.questionSkipResponse(
                    isFromPermission: pending.isFromPermission
                )
            )
        }
        let sessionId = pending.event.sessionId ?? "default"
        sessions[sessionId]?.status = BlockingInteractionCoordinator.statusAfterQuestionResolution()

        showNextPending()
        refreshDerivedState()
        return true
    }

    func showNextPending() {
        guard let nextState = BlockingInteractionCoordinator.nextPresentation(
            permissionQueue: permissionQueue,
            questionQueue: questionQueue,
            currentSurface: surface
        ) else { return }

        if let activeSessionId = nextState.activeSessionId {
            self.activeSessionId = activeSessionId
        }
        presentSurface(nextState.surface, reason: .notification)
    }

    func mostActiveSessionId() -> String? {
        activeSessionIdsByActivity.first
    }
}
