import Foundation
import Darwin
import SuperIslandCore

extension AppState {
    func cleanupIdleSessions() {
        var orphaned: [(String, pid_t)] = []
        for (sessionId, monitor) in processMonitors {
            let pid = monitor.pid
            var info = proc_bsdinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            if ret > 0 && info.pbi_ppid <= 1 {
                orphaned.append((sessionId, pid))
            }
        }
        for (sessionId, pid) in orphaned {
            Self.debugLog("cleanupIdleSessions: remove orphaned session \(sessionId) pid=\(pid)")
            kill(pid, SIGTERM)
            removeSession(sessionId)
        }

        for (key, session) in sessions where session.status != .idle && session.status != .waitingApproval && session.status != .waitingQuestion {
            if processMonitors[key] != nil { continue }
            let elapsed = -session.lastActivity.timeIntervalSinceNow
            let shouldReset = (session.status == .processing && session.currentTool == nil && elapsed > 60)
                || elapsed > 180
            if shouldReset {
                Self.debugLog("cleanupIdleSessions: reset stuck session \(key) status=\(String(describing: session.status)) elapsed=\(elapsed)")
                sessions[key]?.status = .idle
                sessions[key]?.currentTool = nil
                sessions[key]?.toolDescription = nil
            }
        }

        let userTimeout = SettingsManager.shared.sessionTimeout
        Self.debugLog("cleanupIdleSessions: userTimeout=\(userTimeout) minutes, checking \(self.sessions.count) sessions")
        for (key, session) in sessions where session.status == .idle {
            if session.isHistoricalSnapshot { continue }
            let idleMinutes = Int(-session.lastActivity.timeIntervalSinceNow / 60)
            if userTimeout > 0 && idleMinutes >= userTimeout {
                Self.debugLog("cleanupIdleSessions: remove timed-out session \(key) idle=\(idleMinutes)min")
                removeSession(key)
            }
        }
        refreshDerivedState()
    }

    func monitorProcess(sessionId: String, pid: pid_t) {
        guard processMonitors[sessionId] == nil else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self, self.sessions[sessionId] != nil else { return }
                self.handleProcessExit(sessionId: sessionId, exitedPid: pid)
            }
        }
        source.resume()
        processMonitors[sessionId] = (source: source, pid: pid)

        if kill(pid, 0) != 0 && errno == ESRCH {
            handleProcessExit(sessionId: sessionId, exitedPid: pid)
        }
    }

    private func handleProcessExit(sessionId: String, exitedPid: pid_t) {
        stopMonitor(sessionId)

        let exitTime = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, self.sessions[sessionId] != nil else { return }

            if self.processMonitors[sessionId] != nil { return }

            if let lastActivity = self.sessions[sessionId]?.lastActivity,
               lastActivity > exitTime { return }

            self.removeSession(sessionId)
        }
    }

    func stopMonitor(_ sessionId: String) {
        processMonitors[sessionId]?.source.cancel()
        processMonitors.removeValue(forKey: sessionId)
    }

    func scheduleTerminalIndexPersist(sessionId: String) {
        pendingTerminalIndexSessionIds.insert(sessionId)
        guard terminalIndexFlushTask == nil else { return }
        terminalIndexFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                self?.flushPendingTerminalIndexPersist()
            }
        }
    }

    func flushPendingTerminalIndexPersist() {
        terminalIndexFlushTask?.cancel()
        terminalIndexFlushTask = nil
        guard !pendingTerminalIndexSessionIds.isEmpty else { return }

        let sessionIds = pendingTerminalIndexSessionIds
        pendingTerminalIndexSessionIds.removeAll()

        let batch = sessionIds.reduce(into: [String: SessionSnapshot]()) { partial, sessionId in
            if let session = sessions[sessionId] {
                partial[sessionId] = session
            }
        }
        sessionTerminalIndexStore.persist(sessions: batch)
    }

    /// Every removal path goes through here so leaked continuations / connections are impossible.
    func removeSession(_ sessionId: String) {
        Self.debugLog("removeSession: \(sessionId)")
        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)
        let providerSessionId = sessions[sessionId]?.providerSessionId

        if surface.sessionId == sessionId {
            showNextPending()
        }
        sessions.removeValue(forKey: sessionId)
        pendingCompletionReviewSessionIds.remove(sessionId)
        stopMonitor(sessionId)
        pendingTerminalIndexSessionIds.remove(sessionId)
        if let providerSessionId {
            codexRefreshService.removeLatestTurnIds(for: [sessionId, providerSessionId])
        } else {
            codexRefreshService.removeLatestTurnIds(for: [sessionId])
        }
        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }
        startRotationIfNeeded()
        refreshDerivedState()
    }

    /// Start monitoring the CLI process for a session.
    func tryMonitorSession(_ sessionId: String) {
        guard processMonitors[sessionId] == nil else { return }
        guard let session = sessions[sessionId],
              shouldMonitorProcessLifecycle(for: session) else { return }

        if let pid = session.cliPid, pid > 0, kill(pid, 0) == 0 {
            monitorProcess(sessionId: sessionId, pid: pid)
            return
        }

        guard let cwd = session.cwd else { return }
        Task.detached {
            let pid = Self.findPidForCwd(cwd)
            await MainActor.run { [weak self] in
                guard let self = self, let pid = pid,
                      self.sessions[sessionId] != nil else { return }
                self.monitorProcess(sessionId: sessionId, pid: pid)
            }
        }
    }

    func shouldMonitorProcessLifecycle(for session: SessionSnapshot) -> Bool {
        session.source != "cursor"
    }

    nonisolated static func findPidForCwd(_ cwd: String) -> pid_t? {
        for pid in ClaudeSessionDiscovery.findPIDs() {
            if SessionProcessInspector.cwd(for: pid) == cwd { return pid }
        }
        return nil
    }

    static func detectCursorYoloMode() -> Bool {
        let settingsPath = NSHomeDirectory() + "/Library/Application Support/Cursor/User/settings.json"
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath),
              let data = fm.contents(atPath: settingsPath),
              let str = String(data: data, encoding: .utf8) else { return false }
        let stripped = ConfigInstaller.stripJSONComments(str)
        guard let strippedData = stripped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: strippedData) as? [String: Any] else { return false }
        if json["cursor.general.yoloMode"] as? Bool == true { return true }
        if json["cursor.agent.enableYoloMode"] as? Bool == true { return true }
        return false
    }

    static func readModelFromTranscript(sessionId: String, cwd: String?) -> String? {
        guard let cwd = cwd else { return nil }
        let projectDir = cwd.claudeProjectDirEncoded()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects/\(projectDir)/\(sessionId).jsonl"
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let chunk = handle.readData(ofLength: 32768)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String, !model.isEmpty
            else { continue }
            return model
        }
        return nil
    }
}
