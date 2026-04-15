import Foundation
import SwiftUI
import SuperIslandCore

extension AppState {
    func startSessionDiscovery() {
        Self.debugLog("startSessionDiscovery: entering")
        startCodexRefreshLoop()
        sessionDiscoveryService.start(
            onCleanup: { [weak self] in
                self?.cleanupIdleSessions()
            },
            restoreStartup: { [weak self] in
                let persisted = SessionPersistence.load()
                let historicalCodexSessions = ConfigInstaller.isEnabled(source: "codex")
                    ? CodexSessionHistoryLoader.loadRecentSessions()
                    : []
                Self.debugLog("startSessionDiscovery: loaded persisted=\(persisted.count), historicalCodex=\(historicalCodexSessions.count)")
                await MainActor.run { [weak appState = self] in
                    appState?.restoreStartupSessions(
                        persisted: persisted,
                        historicalCodexSessions: historicalCodexSessions
                    )
                }
            },
            scanLiveSessions: { [weak self] in
                let claudeSessions = ConfigInstaller.isEnabled(source: "claude") ? ClaudeSessionDiscovery.findActiveSessions() : []
                let codexSessions = ConfigInstaller.isEnabled(source: "codex") ? CodexSessionDiscovery.findActiveSessions() : []
                await MainActor.run { [weak appState = self] in
                    appState?.integrateDiscovered(claudeSessions)
                    appState?.integrateDiscovered(codexSessions)
                }
            }
        )
    }

    func integrateDiscovered(_ discovered: [DiscoveredSession]) {
        var didAdd = false
        var discoveredCodex = false
        for info in discovered {
            if info.source == "codex" {
                discoveredCodex = true
            }
            if SessionFilter.shouldIgnoreSession(source: info.source, cwd: info.cwd, termBundleId: nil) {
                continue
            }
            if sessions[info.sessionId] != nil {
                if processMonitors[info.sessionId] == nil, let pid = info.pid {
                    monitorProcess(sessionId: info.sessionId, pid: pid)
                }
                refreshProviderTitle(for: info.sessionId, providerSessionId: info.sessionId)
                continue
            }

            let duplicateKey = sessions.first(where: { (_, existing) in
                guard existing.source == info.source,
                      existing.cwd != nil, existing.cwd == info.cwd else { return false }
                if let discoveredPid = info.pid, let existingPid = existing.cliPid,
                   discoveredPid != existingPid { return false }
                return true
            })?.key

            if let existingKey = duplicateKey {
                if let pid = info.pid, processMonitors[existingKey] == nil {
                    monitorProcess(sessionId: existingKey, pid: pid)
                }
                refreshProviderTitle(for: existingKey, providerSessionId: info.sessionId)
                continue
            }

            var session = SessionSnapshot(startTime: info.modifiedAt)
            session.cwd = info.cwd
            session.model = info.model
            session.ttyPath = info.tty
            session.recentMessages = info.recentMessages
            session.source = info.source
            session.providerSessionId = SessionTitleStore.supports(provider: info.source) ? info.sessionId : nil
            if let last = info.recentMessages.last(where: { $0.isUser }) {
                session.lastUserPrompt = last.text
            }
            if let last = info.recentMessages.last(where: { !$0.isUser }) {
                session.lastAssistantMessage = last.text
            }
            session = sessionTerminalIndexStore.hydrate(session, sessionId: info.sessionId)
            sessions[info.sessionId] = session
            refreshProviderTitle(for: info.sessionId, providerSessionId: info.sessionId)
            if let pid = info.pid {
                monitorProcess(sessionId: info.sessionId, pid: pid)
            }
            scheduleTerminalIndexPersist(sessionId: info.sessionId)
            didAdd = true
        }
        if didAdd && activeSessionId == nil {
            activeSessionId = mostActiveSessionId()
        }
        refreshDerivedState()
        if discoveredCodex {
            requestCodexRefresh(minimumInterval: didAdd ? 0 : 2)
        }
    }

    func stopSessionDiscovery() {
        codexRefreshService.stop()
        sessionDiscoveryService.stop()
        for key in Array(processMonitors.keys) { stopMonitor(key) }
    }

    func startCodexRefreshLoop() {
        codexRefreshService.startLoop { [weak self] in
            await self?.refreshCodexThreadSnapshots()
        }
    }

    func requestCodexRefresh(minimumInterval: TimeInterval) {
        codexRefreshService.requestRefresh(minimumInterval: minimumInterval) { [weak self] in
            await self?.refreshCodexThreadSnapshots()
        }
    }

    func refreshCodexThreadSnapshots() async {
        let threadIds = trackedCodexThreadIds()
        await codexRefreshService.performRefreshIfNeeded(
            isEnabled: ConfigInstaller.isEnabled(source: "codex"),
            trackedThreadIds: threadIds,
            applySnapshot: { [weak self] snapshot in
                guard let self else { return false }
                guard self.sessions.values.contains(where: { $0.source == "codex" }) else { return false }
                return self.applyCodexThreadSnapshot(snapshot)
            },
            didChange: { [weak self] in
                guard let self else { return }
                self.scheduleSave()
                self.startRotationIfNeeded()
                self.requestDerivedStateRefresh()
            }
        )
    }

    private func trackedCodexThreadIds() -> [String] {
        var seen: Set<String> = []
        return sessions
            .filter { $0.value.source == "codex" }
            .sorted { $0.value.lastActivity > $1.value.lastActivity }
            .compactMap { sessionId, session in
                let threadId = session.providerSessionId ?? sessionId
                guard seen.insert(threadId).inserted else { return nil }
                return threadId
            }
    }

    private func applyCodexThreadSnapshot(_ snapshot: CodexAppThreadSnapshot) -> Bool {
        let trackedSessionId = trackedSessionId(forCodexThreadId: snapshot.threadId, cwd: snapshot.cwd) ?? snapshot.threadId
        var session = sessions[trackedSessionId] ?? SessionSnapshot(startTime: snapshot.updatedAt)
        let previous = session

        session.source = "codex"
        session.providerSessionId = snapshot.threadId
        session.cwd = snapshot.cwd ?? session.cwd
        session.lastActivity = max(session.lastActivity, snapshot.updatedAt)
        session.status = resolvedCodexStatus(
            desired: snapshot.status,
            trackedSessionId: trackedSessionId,
            providerSessionId: snapshot.threadId
        )
        if let title = snapshot.title {
            session.sessionTitle = title
            session.sessionTitleSource = .codexThreadName
        }
        if let text = snapshot.lastUserText {
            session.lastUserPrompt = text
        }
        if let text = snapshot.lastAssistantText {
            session.lastAssistantMessage = text
        }
        if !snapshot.recentMessages.isEmpty {
            session.recentMessages = snapshot.recentMessages
        }
        if let latestTurnId = nonEmpty(snapshot.latestTurnId) {
            codexRefreshService.storeLatestTurnId(latestTurnId, for: [snapshot.threadId, trackedSessionId])
        }

        sessions[trackedSessionId] = session
        scheduleTerminalIndexPersist(sessionId: trackedSessionId)
        if snapshot.title == nil {
            refreshProviderTitle(for: trackedSessionId, providerSessionId: snapshot.threadId)
        }
        if activeSessionId == nil || sessions[activeSessionId ?? ""]?.status == .idle {
            activeSessionId = mostActiveSessionId()
        }
        return codexSessionChanged(previous: previous, current: session)
    }

    func trackedSessionId(forCodexThreadId threadId: String, cwd: String?) -> String? {
        if let session = sessions[threadId], session.source == "codex" {
            return threadId
        }

        if let match = sessions.first(where: { sessionId, session in
            session.source == "codex"
                && (sessionId == threadId || session.providerSessionId == threadId)
        })?.key {
            return match
        }

        if let cwd {
            return sessions.first(where: { _, session in
                session.source == "codex" && session.cwd == cwd
            })?.key
        }

        return nil
    }

    private func resolvedCodexStatus(desired: AgentStatus, trackedSessionId: String, providerSessionId: String) -> AgentStatus {
        let identifiers = Set([trackedSessionId, providerSessionId])
        if permissionQueue.contains(where: { identifiers.contains($0.event.sessionId ?? "") }) {
            return .waitingApproval
        }
        if questionQueue.contains(where: { identifiers.contains($0.event.sessionId ?? "") }) {
            return .waitingQuestion
        }
        return desired
    }

    private func codexSessionChanged(previous: SessionSnapshot, current: SessionSnapshot) -> Bool {
        previous.status != current.status
            || previous.cwd != current.cwd
            || previous.lastActivity != current.lastActivity
            || previous.lastUserPrompt != current.lastUserPrompt
            || previous.lastAssistantMessage != current.lastAssistantMessage
            || recentMessagesChanged(previous.recentMessages, current.recentMessages)
            || previous.sessionTitle != current.sessionTitle
            || previous.sessionTitleSource != current.sessionTitleSource
            || previous.providerSessionId != current.providerSessionId
    }

    private func recentMessagesChanged(_ lhs: [ChatMessage], _ rhs: [ChatMessage]) -> Bool {
        guard lhs.count == rhs.count else { return true }
        return zip(lhs, rhs).contains { left, right in
            left.isUser != right.isUser || left.text != right.text
        }
    }
}
