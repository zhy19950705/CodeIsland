import Foundation
import SuperIslandCore

private struct RestoredSessionCandidate {
    let sessionId: String
    let snapshot: SessionSnapshot
    let shouldAttachProcessMonitor: Bool
}

extension AppState {
    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveSessions()
            }
        }
    }

    func saveSessions(synchronously: Bool = false) {
        let sessions = self.sessions
        if synchronously {
            SessionPersistence.save(sessions)
            return
        }

        Task.detached(priority: .utility) {
            SessionPersistence.save(sessions)
        }
    }

    nonisolated static func debugLog(_ message: String) {
        print("[SUPERISLAND DEBUG] \(message)")
        let path = "/tmp/superisland_debug.log"
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? (existing + message + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    func applyRestoredSessions(
        persisted: [PersistedSession],
        historicalCodexSessions: [(sessionId: String, snapshot: SessionSnapshot)] = []
    ) {
        Self.debugLog("applyRestoredSessions: persisted=\(persisted.count), historical=\(historicalCodexSessions.count)")
        let cutoff = restoredSessionCutoff()
        let persistedCandidates = persisted
            .filter { candidate in
                guard let cutoff else { return true }
                return candidate.lastActivity > cutoff
            }
            .sorted { $0.lastActivity > $1.lastActivity }
            .compactMap { persistedSession -> RestoredSessionCandidate? in
                let result = self.candidate(from: persistedSession)
                if result == nil {
                    Self.debugLog("applyRestoredSessions: dropped persisted session \(persistedSession.sessionId) (source=\(persistedSession.source))")
                }
                return result
            }

        let nonCodexCandidates = persistedCandidates.filter { $0.snapshot.source != "codex" }
        var codexCandidates = persistedCandidates.filter { $0.snapshot.source == "codex" }
        Self.debugLog("applyRestoredSessions: nonCodex=\(nonCodexCandidates.count), codexPersisted=\(codexCandidates.count)")

        for candidate in nonCodexCandidates {
            let inserted = insertRestoredSession(sessionId: candidate.sessionId, snapshot: candidate.snapshot)
            Self.debugLog("applyRestoredSessions: insert nonCodex \(candidate.sessionId) -> \(inserted)")
            guard inserted else { continue }
            refreshProviderTitle(for: candidate.sessionId)
            if candidate.shouldAttachProcessMonitor {
                attachRestoredProcessMonitorIfNeeded(sessionId: candidate.sessionId, snapshot: candidate.snapshot)
            }
        }

        for historical in historicalCodexSessions.sorted(by: { $0.snapshot.lastActivity > $1.snapshot.lastActivity }) {
            let clearedAt = UserDefaults.standard.double(forKey: Self.historicalSessionsClearedAtKey)
            if clearedAt > 0, historical.snapshot.lastActivity.timeIntervalSince1970 <= clearedAt {
                Self.debugLog("applyRestoredSessions: skip historical \(historical.sessionId) (clearedAt)")
                continue
            }
            let snapshot = sessionTerminalIndexStore.hydrate(historical.snapshot, sessionId: historical.sessionId)
            codexCandidates.append(
                RestoredSessionCandidate(
                    sessionId: historical.sessionId,
                    snapshot: snapshot,
                    shouldAttachProcessMonitor: false
                )
            )
        }

        for candidate in codexCandidates.sorted(by: { $0.snapshot.lastActivity > $1.snapshot.lastActivity }) {
            let inserted = insertRestoredSession(sessionId: candidate.sessionId, snapshot: candidate.snapshot)
            Self.debugLog("applyRestoredSessions: insert codex \(candidate.sessionId) -> \(inserted)")
            guard inserted else { continue }
            refreshProviderTitle(
                for: candidate.sessionId,
                providerSessionId: candidate.snapshot.providerSessionId ?? candidate.sessionId
            )
            if candidate.shouldAttachProcessMonitor {
                attachRestoredProcessMonitorIfNeeded(sessionId: candidate.sessionId, snapshot: candidate.snapshot)
            }
        }

        if activeSessionId == nil {
            activeSessionId = mostActiveSessionId()
        }
        Self.debugLog("applyRestoredSessions: sessions after restore=\(self.sessions.count), activeSessionId=\(self.activeSessionId ?? "nil")")
        cleanupIdleSessions()
        Self.debugLog("applyRestoredSessions: sessions after cleanup=\(self.sessions.count)")
    }

    func restoreStartupSessions(
        persisted: [PersistedSession],
        historicalCodexSessions: [(sessionId: String, snapshot: SessionSnapshot)] = []
    ) {
        applyRestoredSessions(
            persisted: persisted,
            historicalCodexSessions: historicalCodexSessions
        )
        guard !sessions.isEmpty else { return }
        saveSessions(synchronously: true)
    }

    private func restoredSessionCutoff(referenceDate: Date = Date()) -> Date? {
        let timeoutMinutes = SettingsManager.shared.sessionTimeout
        guard timeoutMinutes > 0 else { return nil }
        return referenceDate.addingTimeInterval(TimeInterval(-timeoutMinutes * 60))
    }

    @discardableResult
    func insertRestoredSession(sessionId: String, snapshot: SessionSnapshot) -> Bool {
        guard sessions[sessionId] == nil else {
            Self.debugLog("insertRestoredSession: skip \(sessionId) (already exists)")
            return false
        }
        if let dup = restoredSessionDuplicateKey(for: sessionId, snapshot: snapshot) {
            Self.debugLog("insertRestoredSession: skip \(sessionId) (duplicate of \(dup))")
            return false
        }
        sessions[sessionId] = snapshot
        Self.debugLog("insertRestoredSession: inserted \(sessionId)")
        return true
    }

    func restoredSessionDuplicateKey(for sessionId: String, snapshot: SessionSnapshot) -> String? {
        let incomingProviderSessionId = snapshot.providerSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let directMatch = sessions.first(where: { existingKey, existing in
            guard existing.source == snapshot.source else { return false }

            let existingProviderSessionId = existing.providerSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let directIDs = [sessionId, incomingProviderSessionId]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            if directIDs.contains(existingKey) {
                return true
            }

            if let existingProviderSessionId, directIDs.contains(existingProviderSessionId) {
                return true
            }

            return false
        })?.key {
            return directMatch
        }

        guard snapshot.source == "codex",
              let cwd = snapshot.cwd,
              !cwd.isEmpty else {
            return nil
        }

        return sessions.first(where: { _, existing in
            guard existing.source == "codex",
                  existing.cwd == cwd else {
                return false
            }

            if let existingPid = existing.cliPid,
               let incomingPid = snapshot.cliPid {
                return existingPid == incomingPid
            }

            return existing.isHistoricalSnapshot
                || snapshot.isHistoricalSnapshot
                || existing.cliPid == nil
                || snapshot.cliPid == nil
        })?.key
    }

    private func candidate(from persisted: PersistedSession) -> RestoredSessionCandidate? {
        guard let source = SessionSnapshot.normalizedSupportedSource(persisted.source) else { return nil }
        guard !SessionFilter.shouldIgnoreSession(source: source, cwd: persisted.cwd, termBundleId: persisted.termBundleId) else {
            return nil
        }

        var snapshot = SessionSnapshot(startTime: persisted.startTime)
        snapshot.cwd = persisted.cwd
        snapshot.source = source
        snapshot.model = persisted.model
        snapshot.sessionTitle = persisted.sessionTitle
        snapshot.sessionTitleSource = persisted.sessionTitleSource
        snapshot.providerSessionId = persisted.providerSessionId
        snapshot.lastUserPrompt = persisted.lastUserPrompt
        snapshot.lastAssistantMessage = persisted.lastAssistantMessage
        if let prompt = persisted.lastUserPrompt {
            snapshot.addRecentMessage(ChatMessage(isUser: true, text: prompt))
        }
        if let reply = persisted.lastAssistantMessage {
            snapshot.addRecentMessage(ChatMessage(isUser: false, text: reply))
        }
        snapshot.termApp = persisted.termApp
        snapshot.itermSessionId = persisted.itermSessionId
        snapshot.ttyPath = persisted.ttyPath
        snapshot.kittyWindowId = persisted.kittyWindowId
        snapshot.tmuxPane = persisted.tmuxPane
        snapshot.tmuxClientTty = persisted.tmuxClientTty
        snapshot.cmuxWorkspaceRef = persisted.cmuxWorkspaceRef
        snapshot.cmuxSurfaceRef = persisted.cmuxSurfaceRef
        snapshot.cmuxPaneRef = persisted.cmuxPaneRef
        snapshot.cmuxWorkspaceId = persisted.cmuxWorkspaceId
        snapshot.cmuxSurfaceId = persisted.cmuxSurfaceId
        snapshot.cmuxSocketPath = persisted.cmuxSocketPath
        snapshot.termBundleId = persisted.termBundleId
        snapshot.lastActivity = persisted.lastActivity
        if let pid = persisted.cliPid, pid > 0 {
            snapshot.cliPid = pid
        }
        snapshot = sessionTerminalIndexStore.hydrate(snapshot, sessionId: persisted.sessionId)

        return RestoredSessionCandidate(
            sessionId: persisted.sessionId,
            snapshot: snapshot,
            shouldAttachProcessMonitor: true
        )
    }

    func attachRestoredProcessMonitorIfNeeded(sessionId: String, snapshot: SessionSnapshot) {
        guard shouldMonitorProcessLifecycle(for: snapshot) else { return }

        if let pid = snapshot.cliPid, pid > 0, kill(pid, 0) == 0 {
            monitorProcess(sessionId: sessionId, pid: pid)
            return
        }

        let sid = sessionId
        Task.detached {
            let pid = Self.findPidForCwd(snapshot.cwd ?? "")
            await MainActor.run { [weak self] in
                guard let self = self, let pid = pid,
                      self.sessions[sid] != nil,
                      self.processMonitors[sid] == nil else { return }
                self.monitorProcess(sessionId: sid, pid: pid)
                self.refreshDerivedState()
            }
        }
    }
}
