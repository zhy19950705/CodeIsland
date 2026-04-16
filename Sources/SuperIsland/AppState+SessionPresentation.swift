import SwiftUI
import os.log
import SuperIslandCore

struct SessionListCacheKey: Hashable {
    let groupingMode: String
    let onlySessionId: String?
}

struct CachedSessionListPresentation {
    let revision: UInt64
    let snapshot: SessionListPresentationSnapshot
}

extension AppState {
    // MARK: - Compact bar mascot rotation

    /// Active session IDs sorted by latest activity, newest first.
    func refreshActiveSessionIndex() {
        activeSessionIdsByActivity = sessions.keys.sorted { lhs, rhs in
            guard let left = sessions[lhs], let right = sessions[rhs] else {
                return lhs < rhs
            }
            if left.status == .idle, right.status != .idle { return false }
            if left.status != .idle, right.status == .idle { return true }
            if left.lastActivity != right.lastActivity {
                return left.lastActivity > right.lastActivity
            }
            return lhs < rhs
        }
        .filter { sessions[$0]?.status != .idle }
    }

    func startRotationIfNeeded() {
        if activeSessionIdsByActivity.count > 1 {
            if rotatingSessionId == nil || !activeSessionIdsByActivity.contains(rotatingSessionId!) {
                rotatingSessionId = activeSessionIdsByActivity.first
            }
            if rotationTimer == nil {
                rotationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.rotateToNextSession()
                    }
                }
            }
        } else {
            rotationTimer?.invalidate()
            rotationTimer = nil
            rotatingSessionId = nil
        }
    }

    private func rotateToNextSession() {
        guard activeSessionIdsByActivity.count > 1 else {
            rotatingSessionId = nil
            return
        }
        if let current = rotatingSessionId, let idx = activeSessionIdsByActivity.firstIndex(of: current) {
            rotatingSessionId = activeSessionIdsByActivity[(idx + 1) % activeSessionIdsByActivity.count]
        } else {
            rotatingSessionId = activeSessionIdsByActivity.first
        }
    }

    var currentTool: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.currentTool
    }

    var toolDescription: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.toolDescription
    }

    var activeDisplayName: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        let displaySessionId = s.displaySessionId(sessionId: id)
        return s.displayTitle(sessionId: displaySessionId)
    }

    var activeModel: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.model
    }

    var preferredSessionId: String? {
        mostActiveSessionId() ?? sessions.keys.sorted().first
    }

    var canContinueActiveCodexSession: Bool {
        guard let sessionId = activeSessionId, let session = sessions[sessionId], session.source == "codex" else {
            return false
        }
        guard pendingPermission?.event.sessionId != sessionId else { return false }
        guard pendingQuestion?.event.sessionId != sessionId else { return false }
        let threadId = session.providerSessionId ?? sessionId
        return codexRefreshService.hasLatestTurnId(for: [threadId, sessionId])
    }

    func sendPromptToActiveSession(_ text: String) {
        guard let sessionId = activeSessionId else { return }
        sendPromptToSession(sessionId, text: text)
    }

    func sendPromptToSession(_ sessionId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var session = sessions[sessionId],
              session.source == "codex" else { return }

        let threadId = session.providerSessionId ?? sessionId
        guard let expectedTurnId = codexRefreshService.latestTurnId(for: [threadId, sessionId]) else {
            requestCodexRefresh(minimumInterval: 0)
            return
        }

        session.status = .processing
        session.lastActivity = Date()
        session.lastUserPrompt = trimmed
        session.currentTool = nil
        session.toolDescription = nil
        session.addRecentMessage(ChatMessage(isUser: true, text: trimmed))
        sessions[sessionId] = session
        acknowledgePendingCompletionReview(for: sessionId)
        activeSessionId = sessionId
        if case .collapsed = surface {
            // Prompt submission is an explicit user action, so reopen through the coordinator to keep state synchronized.
            panelCoordinator.openSessionList(reason: .click)
        }
        scheduleTerminalIndexPersist(sessionId: sessionId)
        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()

        Task { [weak self] in
            do {
                try await CodexAppServerClient.shared.continueThread(
                    threadId: threadId,
                    expectedTurnId: expectedTurnId,
                    text: trimmed
                )
                await MainActor.run {
                    self?.requestCodexRefresh(minimumInterval: 0)
                }
            } catch {
                await MainActor.run {
                    Logger(subsystem: "com.superisland", category: "AppState").error(
                        "Codex continue failed for \(threadId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    self?.sessions[sessionId]?.status = .idle
                    self?.refreshDerivedState()
                }
            }
        }
    }

    @discardableResult
    func activateSession(_ sessionId: String) -> Bool {
        guard sessions[sessionId] != nil else { return false }
        acknowledgePendingCompletionReview(for: sessionId)
        activeSessionId = sessionId
        startRotationIfNeeded()
        refreshDerivedState()
        return true
    }

    @discardableResult
    func focusSession(sessionId: String) -> Bool {
        panelCoordinator.focusSession(sessionId: sessionId)
    }

    /// Open a dedicated session detail surface so long transcripts do not resize the list view itself.
    func showSessionDetail(_ sessionId: String, reason: IslandOpenReason = .click) {
        panelCoordinator.showSessionDetail(sessionId: sessionId, reason: reason)
    }

    func jumpToSession(_ sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        acknowledgePendingCompletionReview(for: sessionId)
        // Auto-resume is only an optimization; if it fails we must keep the original jump fallback path.
        if shouldAutoResumeOnJump(for: session, sessionId: sessionId),
           SessionJumpRouter.resume(to: session, sessionId: sessionId) {
            return
        }
        guard shouldValidateCodexJump(for: session) else {
            SessionJumpRouter.jump(to: session, sessionId: sessionId)
            return
        }

        // Codex rows can outlive the backing thread, so validate once before deep-linking into the app.
        Task { [weak self] in
            do {
                let threadId = session.providerSessionId ?? sessionId
                _ = try await CodexAppServerClient.shared.readThread(threadId: threadId)
                await MainActor.run {
                    guard let self, let latestSession = self.sessions[sessionId] else { return }
                    SessionJumpRouter.jump(to: latestSession, sessionId: sessionId)
                }
            } catch {
                await MainActor.run {
                    guard let self, let latestSession = self.sessions[sessionId] else { return }

                    if SessionResumeSupport.isMissingCodexThreadError(error),
                       SessionJumpRouter.resume(to: latestSession, sessionId: sessionId) {
                        return
                    }

                    // Transport failures should not block the original jump path, otherwise a healthy thread becomes unreachable.
                    SessionJumpRouter.jump(to: latestSession, sessionId: sessionId)
                }
            }
        }
    }

    func needsCompletionReview(sessionId: String) -> Bool {
        pendingCompletionReviewSessionIds.contains(sessionId)
    }

    @discardableResult
    func focusSession(cwd: String?, source: String?) -> String? {
        let match = matchingSessionId(cwd: cwd, source: source)
        guard let match, panelCoordinator.focusSession(sessionId: match) else { return nil }
        return match
    }

    func sessionListPresentation(groupingMode: String, onlySessionId: String? = nil) -> SessionListPresentationSnapshot {
        let key = SessionListCacheKey(groupingMode: groupingMode, onlySessionId: onlySessionId)
        if let cached = cachedSessionListPresentations[key],
           cached.revision == sessionListCacheRevision {
            return cached.snapshot
        }

        let snapshot = buildSessionListPresentation(groupingMode: groupingMode, onlySessionId: onlySessionId)
        cachedSessionListPresentations[key] = CachedSessionListPresentation(
            revision: sessionListCacheRevision,
            snapshot: snapshot
        )
        return snapshot
    }

    private func buildSessionListPresentation(groupingMode: String, onlySessionId: String?) -> SessionListPresentationSnapshot {
        if let onlySessionId {
            guard sessions[onlySessionId] != nil else { return .empty }
            return SessionListPresentationSnapshot(
                groups: [
                    SessionListGroupPresentation(
                        id: "session-only-\(onlySessionId)",
                        header: "",
                        source: nil,
                        ids: [onlySessionId]
                    )
                ],
                totalSessionCount: 1,
                groupHeaderCount: 0
            )
        }

        let allIds = Array(sessions.keys)
        let support = SessionGroupingSupport(
            sessions: sessions,
            sortIDs: { [weak self] ids in
                self?.sortedSessionIDsByActivity(ids) ?? ids.sorted()
            },
            latestActivity: { [weak self] ids in
                self?.latestActivity(for: ids) ?? .distantPast
            }
        )
        let groups = SessionGroupingStrategies
            .strategy(for: groupingMode)
            .makeGroups(allIDs: allIds, support: support)

        let totalSessionCount = groups.reduce(0) { partial, group in
            partial + group.ids.count
        }
        let groupHeaderCount = groups.reduce(0) { partial, group in
            partial + (group.header.isEmpty ? 0 : 1)
        }

        return SessionListPresentationSnapshot(
            groups: groups,
            totalSessionCount: totalSessionCount,
            groupHeaderCount: groupHeaderCount
        )
    }

    private func sortedSessionIDsByActivity(_ ids: [String]) -> [String] {
        ids.sorted { lhs, rhs in
            guard let left = sessions[lhs], let right = sessions[rhs] else { return lhs < rhs }

            let leftNeedsAttention = left.status == .waitingApproval || left.status == .waitingQuestion
            let rightNeedsAttention = right.status == .waitingApproval || right.status == .waitingQuestion
            if leftNeedsAttention != rightNeedsAttention {
                return leftNeedsAttention
            }

            let leftNeedsReview = pendingCompletionReviewSessionIds.contains(lhs)
            let rightNeedsReview = pendingCompletionReviewSessionIds.contains(rhs)
            if leftNeedsReview != rightNeedsReview {
                return leftNeedsReview
            }

            let leftIsActiveSession = lhs == activeSessionId
            let rightIsActiveSession = rhs == activeSessionId
            if leftIsActiveSession != rightIsActiveSession {
                return leftIsActiveSession
            }

            let leftActive = left.status != .idle
            let rightActive = right.status != .idle
            if leftActive != rightActive {
                return leftActive
            }

            if left.lastActivity != right.lastActivity {
                return left.lastActivity > right.lastActivity
            }
            return lhs < rhs
        }
    }

    private func latestActivity(for ids: [String]) -> Date {
        ids.compactMap { sessions[$0]?.lastActivity }.max() ?? .distantPast
    }

    /// Recompute cached status/source/counts from sessions in a single O(n) pass.
    /// Call after any mutation to `sessions` or session status.
    func refreshDerivedState() {
        pendingDerivedStateRefreshTask?.cancel()
        pendingDerivedStateRefreshTask = nil
        lastDerivedStateRefreshAt = Date()

        let summary = deriveSessionSummary(from: sessions)
        var didChange = false
        if status != summary.status {
            status = summary.status
            didChange = true
        }
        if primarySource != summary.primarySource {
            primarySource = summary.primarySource
            didChange = true
        }
        if activeSessionCount != summary.activeSessionCount {
            activeSessionCount = summary.activeSessionCount
            didChange = true
        }
        if totalSessionCount != summary.totalSessionCount {
            totalSessionCount = summary.totalSessionCount
            didChange = true
        }
        if didChange {
            notifyPanelStateChanged()
        }
    }

    func requestDerivedStateRefresh() {
        let now = Date()
        let minimumInterval = AppRuntimeConstants.derivedStateRefreshInterval

        guard let delay = Self.derivedStateRefreshDelay(
            now: now,
            lastRefreshAt: lastDerivedStateRefreshAt,
            minimumInterval: minimumInterval
        ) else {
            refreshDerivedState()
            return
        }

        guard pendingDerivedStateRefreshTask == nil else { return }

        // Coalesce dense hook bursts into one follow-up refresh to reduce unnecessary O(n) recomputation.
        pendingDerivedStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                guard let self else { return }
                self.refreshDerivedState()
            }
        }
    }

    nonisolated static func derivedStateRefreshDelay(
        now: Date,
        lastRefreshAt: Date,
        minimumInterval: TimeInterval = AppRuntimeConstants.derivedStateRefreshInterval
    ) -> TimeInterval? {
        let elapsed = now.timeIntervalSince(lastRefreshAt)
        guard elapsed < minimumInterval else { return nil }
        return max(0, minimumInterval - elapsed)
    }

    func invalidateSessionListPresentationCache() {
        sessionListCacheRevision &+= 1
        cachedSessionListPresentations.removeAll(keepingCapacity: true)
    }

    func notifyPanelStateChanged() {
        NotificationCenter.default.post(name: .superIslandPanelStateDidChange, object: self)
    }

    func refreshProviderTitle(for trackedSessionId: String, providerSessionId: String? = nil) {
        guard let session = sessions[trackedSessionId] else { return }

        let lookupSessionId = providerSessionId ?? session.providerSessionId ?? trackedSessionId
        if let providerSessionId {
            sessions[trackedSessionId]?.providerSessionId = providerSessionId
        } else if SessionTitleStore.supports(provider: session.source) {
            sessions[trackedSessionId]?.providerSessionId = lookupSessionId
        }

        guard SessionTitleStore.supports(provider: session.source) else { return }

        if let resolved = SessionTitleStore.title(for: lookupSessionId, provider: session.source, cwd: session.cwd) {
            sessions[trackedSessionId]?.sessionTitle = resolved.title
            sessions[trackedSessionId]?.sessionTitleSource = resolved.source
        } else {
            sessions[trackedSessionId]?.sessionTitle = nil
            sessions[trackedSessionId]?.sessionTitleSource = nil
        }
    }

    func loadTestingScenario(_ scenario: PreviewScenario) {
        clearTestingScenarios()
        DebugHarness.apply(scenario, to: self)

        if scenario == .approval {
            previewApprovalPayload = ApprovalPreviewPayload(
                tool: "Bash",
                toolInput: ["command": "npm run test -- --coverage"]
            )
        }

        if surface == .collapsed && !sessions.isEmpty {
            // Preview scenarios should use the same panel entry policy as runtime opens.
            panelCoordinator.openSessionList(reason: .boot)
        }

        refreshDerivedState()
    }

    func clearTestingScenarios() {
        let previewSessionIDs = sessions.keys.filter { $0.hasPrefix(Self.testingSessionPrefix) }
        for sessionId in previewSessionIDs {
            sessions.removeValue(forKey: sessionId)
            stopMonitor(sessionId)
            pendingTerminalIndexSessionIds.remove(sessionId)
        }

        previewQuestionPayload = nil
        previewApprovalPayload = nil
        completionQueue.removeAll { $0.hasPrefix(Self.testingSessionPrefix) }
        pendingCompletionReviewSessionIds = pendingCompletionReviewSessionIds.filter { !$0.hasPrefix(Self.testingSessionPrefix) }

        if let activeSessionId, activeSessionId.hasPrefix(Self.testingSessionPrefix) {
            self.activeSessionId = mostActiveSessionId()
        }

        if let sessionId = surface.sessionId, sessionId.hasPrefix(Self.testingSessionPrefix) {
            if sessions.isEmpty {
                // Testing cleanup should reset the panel through the same coordinator path as runtime teardown.
                panelCoordinator.collapse(reason: .unknown)
            } else {
                // Testing cleanup should restore the default list surface through the coordinator.
                panelCoordinator.openSessionList(reason: .unknown)
            }
        }

        startRotationIfNeeded()
        refreshDerivedState()
    }

    func clearAllSessionRecords() {
        cancelCompletionQueue()
        terminalIndexFlushTask?.cancel()
        terminalIndexFlushTask = nil
        pendingTerminalIndexSessionIds.removeAll()

        for key in Array(processMonitors.keys) {
            stopMonitor(key)
        }

        permissionQueue.removeAll()
        questionQueue.removeAll()
        previewQuestionPayload = nil
        previewApprovalPayload = nil
        sessions.removeAll()
        pendingCompletionReviewSessionIds.removeAll()
        activeSessionId = nil
        rotatingSessionId = nil
        // Global session reset is a presentation transition, so keep it routed through the panel coordinator.
        panelCoordinator.collapse(reason: .unknown)
        codexRefreshService.clearLatestTurnIds()

        SessionPersistence.clear()
        sessionTerminalIndexStore.clear()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.historicalSessionsClearedAtKey)

        refreshDerivedState()
    }
}
