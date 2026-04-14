import SwiftUI
import Observation
import CoreServices
import os.log
import SuperIslandCore

private let log = Logger(subsystem: "com.superisland", category: "AppState")

struct SessionListGroupPresentation: Identifiable {
    let id: String
    let header: String
    let source: String?
    let ids: [String]
}

struct SessionListPresentationSnapshot {
    let groups: [SessionListGroupPresentation]
    let totalSessionCount: Int
    let groupHeaderCount: Int

    static let empty = SessionListPresentationSnapshot(
        groups: [],
        totalSessionCount: 0,
        groupHeaderCount: 0
    )
}

private struct SessionListCacheKey: Hashable {
    let groupingMode: String
    let onlySessionId: String?
}

private struct CachedSessionListPresentation {
    let revision: UInt64
    let snapshot: SessionListPresentationSnapshot
}

private struct RestoredSessionCandidate {
    let sessionId: String
    let snapshot: SessionSnapshot
    let shouldAttachProcessMonitor: Bool
}

@MainActor
@Observable
final class AppState {
    private static let testingSessionPrefix = "preview-"
    private static let historicalSessionsClearedAtKey = "historicalSessionsClearedAt"

    var sessions: [String: SessionSnapshot] = [:] {
        didSet {
            invalidateSessionListPresentationCache()
        }
    }
    var activeSessionId: String? {
        didSet {
            guard oldValue != activeSessionId else { return }
            invalidateSessionListPresentationCache()
        }
    }
    var permissionQueue: [PermissionRequest] = []
    var questionQueue: [QuestionRequest] = []

    /// Computed: first item in permission queue (backward compat for UI reads)
    var pendingPermission: PermissionRequest? { permissionQueue.first }
    /// Computed: first item in question queue
    var pendingQuestion: QuestionRequest? { questionQueue.first }
    /// Preview-only: mock question payload for DebugHarness (no continuation needed)
    var previewQuestionPayload: QuestionPayload?
    /// Preview-only: mock approval payload for settings-driven testing.
    var previewApprovalPayload: ApprovalPreviewPayload?
    var surface: IslandSurface = .collapsed {
        didSet {
            guard oldValue != surface else { return }
            notifyPanelStateChanged()
        }
    }

    var justCompletedSessionId: String? {
        if case .completionCard(let id) = surface { return id }
        return nil
    }

    private var maxHistory: Int { SettingsManager.shared.maxToolHistory }
    private var cleanupTimer: Timer?
    private var autoCollapseTask: Task<Void, Never>?
    private var codexRefreshTask: Task<Void, Never>?
    private var completionQueue: [String] = []
    /// Mouse must enter the panel before auto-collapse is allowed (prevents instant dismiss)
    var completionHasBeenEntered = false
    private var processMonitors: [String: (source: DispatchSourceProcess, pid: pid_t)] = [:]
    private var saveTimer: Timer?
    private var terminalIndexFlushTask: Task<Void, Never>?
    private var pendingTerminalIndexSessionIds: Set<String> = []
    private var fsEventStream: FSEventStreamRef?
    private var lastFSScanTime: Date = .distantPast
    private let sessionTerminalIndexStore = SessionTerminalIndexStore()
    private var usageSnapshotObserver: NSObjectProtocol?
    private var codexPermissionObserver: NSObjectProtocol?
    private var codexQuestionObserver: NSObjectProtocol?
    private var codexRefreshObserver: NSObjectProtocol?
    private var codexRefreshInFlight = false
    private var lastCodexRefreshAt: Date = .distantPast
    private var codexLatestTurnIds: [String: String] = [:]
    private var isShowingCompletion: Bool {
        if case .completionCard = surface { return true }
        return false
    }
    private var modelReadAttempted: Set<String> = []
    @ObservationIgnored private var sessionListCacheRevision: UInt64 = 0
    @ObservationIgnored private var cachedSessionListPresentations: [SessionListCacheKey: CachedSessionListPresentation] = [:]
    private(set) var pendingCompletionReviewSessionIds: Set<String> = []

    /// Throttle for tab-level visibility checks to avoid excessive AppleScript calls.
    /// `isSessionTabVisible` uses System Events which can trigger TCC prompts on macOS 15+.
    /// Minimum interval between checks (seconds).
    private let minTabVisibilityCheckInterval: TimeInterval = 2.0
    private var lastTabVisibilityCheckTime: Date = .distantPast
    private var lastTabVisibilityCheckResult: Bool = false

    var rotatingSessionId: String?
    var rotatingSession: SessionSnapshot? {
        guard let rid = rotatingSessionId else { return nil }
        return sessions[rid]
    }
    private var rotationTimer: Timer?
    var usageSnapshot: UsageSnapshot = UsageSnapshotStore.load()

    init() {
        usageSnapshotObserver = NotificationCenter.default.addObserver(
            forName: UsageSnapshotStore.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUsageSnapshot()
            }
        }

        codexPermissionObserver = NotificationCenter.default.addObserver(
            forName: .superIslandCodexPermissionRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleCodexPermissionNotification(note)
            }
        }

        codexQuestionObserver = NotificationCenter.default.addObserver(
            forName: .superIslandCodexQuestionRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleCodexQuestionNotification(note)
            }
        }

        codexRefreshObserver = NotificationCenter.default.addObserver(
            forName: .superIslandCodexThreadRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleCodexRefreshNotification(note)
            }
        }
    }

    func refreshUsageSnapshot() {
        usageSnapshot = UsageSnapshotStore.load()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func diagnosticsSnapshot() -> AppDiagnosticsSnapshot {
        let sessions = self.sessions.map { sessionId, snapshot in
            AppDiagnosticsSnapshot.SessionRecord(
                sessionId: sessionId,
                source: snapshot.source,
                status: String(describing: snapshot.status),
                cwd: snapshot.cwd,
                model: snapshot.model,
                currentTool: snapshot.currentTool,
                termApp: snapshot.termApp,
                termBundleId: snapshot.termBundleId,
                cliPid: snapshot.cliPid,
                lastActivity: snapshot.lastActivity,
                startTime: snapshot.startTime,
                interrupted: snapshot.interrupted,
                isHistoricalSnapshot: snapshot.isHistoricalSnapshot
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }

        return AppDiagnosticsSnapshot(
            exportedAt: Date(),
            activeSessionId: activeSessionId,
            surface: String(describing: surface),
            permissionQueueCount: permissionQueue.count,
            questionQueueCount: questionQueue.count,
            sessions: sessions
        )
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupIdleSessions()
            }
        }
    }

    private func cleanupIdleSessions() {
        // 1. Kill orphaned Claude processes (terminal closed but process survived)
        // Collect first to avoid mutating sessionPids during iteration
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

        // 2. Reset stuck sessions
        //    - processing with no tool (e.g. lost Stop event): 60 seconds
        //    - running/processing with a tool: 3 minutes (long build, deep thinking)
        //    Skip sessions with a live process monitor for the long timeout.
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

        // 3. Remove idle sessions past the user-configured timeout.
        let userTimeout = SettingsManager.shared.sessionTimeout
        Self.debugLog("cleanupIdleSessions: userTimeout=\(userTimeout) minutes, checking \(self.sessions.count) sessions")
        for (key, session) in sessions where session.status == .idle {
            if session.isHistoricalSnapshot { continue }
            let idleMinutes = Int(-session.lastActivity.timeIntervalSinceNow / 60)
            if userTimeout > 0 && idleMinutes >= userTimeout {
                Self.debugLog("cleanupIdleSessions: remove timed-out session \(key) idle=\(idleMinutes)min")
                // User-configured timeout applies to all idle sessions.
                removeSession(key)
            }
        }
        refreshDerivedState()
    }

    // MARK: - Process Monitoring (DispatchSource)

    /// Watch a Claude process for exit — waits a grace period before removing, in case the
    /// process restarts (e.g. auto-update) or a new hook event re-activates the session.
    private func monitorProcess(sessionId: String, pid: pid_t) {
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

        // Safety: if process already exited before monitor started
        if kill(pid, 0) != 0 && errno == ESRCH {
            handleProcessExit(sessionId: sessionId, exitedPid: pid)
        }
    }

    /// Grace period after process exit — gives 5s for a replacement process or fresh hook event
    /// to claim the session before removal. Prevents flicker during agent restarts.
    private func handleProcessExit(sessionId: String, exitedPid: pid_t) {
        // Tear down the dead monitor immediately
        stopMonitor(sessionId)

        let exitTime = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, self.sessions[sessionId] != nil else { return }

            // A new monitor was attached during the grace period (new process took over)
            if self.processMonitors[sessionId] != nil { return }

            // Session received fresh activity during the grace period — still alive
            if let lastActivity = self.sessions[sessionId]?.lastActivity,
               lastActivity > exitTime { return }

            self.removeSession(sessionId)
        }
    }

    private func stopMonitor(_ sessionId: String) {
        processMonitors[sessionId]?.source.cancel()
        processMonitors.removeValue(forKey: sessionId)
    }

    private func scheduleTerminalIndexPersist(sessionId: String) {
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

    /// Remove a session, clean up its monitor, and resume any pending continuations.
    /// Every removal path (cleanup timer, process exit, reducer effect) goes through here
    /// so leaked continuations / connections are impossible.
    private func removeSession(_ sessionId: String) {
        Self.debugLog("removeSession: \(sessionId)")
        // Resume ALL pending continuations for this session
        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)
        let providerSessionId = sessions[sessionId]?.providerSessionId

        if surface.sessionId == sessionId {
            showNextPending()
        }
        sessions.removeValue(forKey: sessionId)
        pendingCompletionReviewSessionIds.remove(sessionId)
        stopMonitor(sessionId)
        codexLatestTurnIds.removeValue(forKey: sessionId)
        pendingTerminalIndexSessionIds.remove(sessionId)
        if let providerSessionId {
            codexLatestTurnIds.removeValue(forKey: providerSessionId)
        }
        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }
        startRotationIfNeeded()
        refreshDerivedState()
    }

    // MARK: - Compact bar mascot rotation

    /// Cached sorted active session IDs — refreshed by refreshActiveIds()
    private var cachedActiveIds: [String] = []

    private func refreshActiveIds() {
        cachedActiveIds = sessions.filter { $0.value.status != .idle }.keys.sorted()
    }

    private func startRotationIfNeeded() {
        refreshActiveIds()
        if cachedActiveIds.count > 1 {
            if rotatingSessionId == nil || !cachedActiveIds.contains(rotatingSessionId!) {
                rotatingSessionId = cachedActiveIds.first
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
        guard cachedActiveIds.count > 1 else {
            rotatingSessionId = nil
            return
        }
        if let current = rotatingSessionId, let idx = cachedActiveIds.firstIndex(of: current) {
            rotatingSessionId = cachedActiveIds[(idx + 1) % cachedActiveIds.count]
        } else {
            rotatingSessionId = cachedActiveIds.first
        }
    }

    /// Start monitoring the CLI process for a session.
    /// Prefers the PID captured by the bridge (_ppid), falls back to scanning for Claude processes by CWD.
    private func tryMonitorSession(_ sessionId: String) {
        guard processMonitors[sessionId] == nil else { return }
        guard let session = sessions[sessionId],
              shouldMonitorProcessLifecycle(for: session) else { return }

        // Primary: use PID from bridge (works for any CLI)
        if let pid = session.cliPid, pid > 0, kill(pid, 0) == 0 {
            monitorProcess(sessionId: sessionId, pid: pid)
            return
        }

        // Fallback: scan for Claude Code processes by CWD
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

    private func shouldMonitorProcessLifecycle(for session: SessionSnapshot) -> Bool {
        // Cursor Desktop launches hook commands under short-lived helper processes.
        // Monitoring that PID makes the session vanish shortly after each hook fires.
        session.source != "cursor"
    }

    /// Find a Claude process PID by matching CWD
    private nonisolated static func findPidForCwd(_ cwd: String) -> pid_t? {
        for pid in findClaudePids() {
            if getCwd(for: pid) == cwd { return pid }
        }
        return nil
    }

    private func enqueueCompletion(_ sessionId: String) {
        markPendingCompletionReview(for: sessionId)
        // Don't queue duplicates
        if completionQueue.contains(sessionId) || justCompletedSessionId == sessionId { return }

        if isShowingCompletion {
            // Already showing one — queue this for later
            completionQueue.append(sessionId)
        } else {
            // Show immediately
            showCompletion(sessionId)
        }
    }

    /// Fast app-level suppress check (main-thread safe, no blocking).
    private func shouldSuppressAppLevel(for sessionId: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKey.smartSuppress) else { return false }
        guard let session = sessions[sessionId],
              (session.termApp != nil || session.termBundleId != nil) else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    private func showCompletion(_ sessionId: String) {
        // Fast path: terminal not even frontmost — show immediately
        guard shouldSuppressAppLevel(for: sessionId) else {
            doShowCompletion(sessionId)
            return
        }

        // Terminal IS frontmost — check tab-level on background thread
        guard let session = sessions[sessionId] else { return }
        let sessionCopy = session

        // Throttle tab-level visibility checks to avoid excessive AppleScript calls.
        // System Events queries can trigger TCC "Screen Recording" prompts on macOS 15+.
        let now = Date()
        let shouldSkipCheck = now.timeIntervalSince(lastTabVisibilityCheckTime) < minTabVisibilityCheckInterval

        Task.detached {
            let tabVisible: Bool
            if shouldSkipCheck {
                // Reuse recent result to avoid TCC churn
                tabVisible = await MainActor.run { [weak self] in self?.lastTabVisibilityCheckResult ?? false }
            } else {
                tabVisible = TerminalVisibilityDetector.isSessionTabVisible(sessionCopy)
                await MainActor.run { [weak self] in
                    self?.lastTabVisibilityCheckTime = now
                    self?.lastTabVisibilityCheckResult = tabVisible
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                // Verify state hasn't changed while we were checking
                // (e.g. approval/question card popped up, session was removed)
                guard self.sessions[sessionId] != nil else { return }
                switch self.surface {
                case .approvalCard, .questionCard: return  // don't overwrite higher-priority surfaces
                default: break
                }
                if !tabVisible {
                    withAnimation(NotchAnimation.pop) {
                        self.doShowCompletion(sessionId)
                    }
                }
            }
        }
    }

    private func doShowCompletion(_ sessionId: String) {
        activeSessionId = sessionId
        surface = .completionCard(sessionId: sessionId)
        completionHasBeenEntered = false
        let displaySeconds = SettingsManager.shared.completionCardDisplaySeconds

        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(displaySeconds))
            guard !Task.isCancelled else { return }
            showNextCompletionOrCollapse()
        }
    }

    func cancelCompletionQueue() {
        autoCollapseTask?.cancel()
        completionQueue.removeAll()
    }

    private func showNextCompletionOrCollapse() {
        while let next = completionQueue.first {
            completionQueue.removeFirst()
            if sessions[next] != nil {
                withAnimation(NotchAnimation.pop) {
                    showCompletion(next)
                }
                return
            }
        }
        withAnimation(NotchAnimation.close) {
            surface = .collapsed
        }
    }

    // Cached derived state (refreshed by refreshDerivedState after session mutations)
    private(set) var status: AgentStatus = .idle
    private(set) var primarySource: String = "claude"
    private(set) var activeSessionCount: Int = 0
    private(set) var totalSessionCount: Int = 0

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
        return codexLatestTurnIds[threadId] != nil || codexLatestTurnIds[sessionId] != nil
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
        guard let expectedTurnId = codexLatestTurnIds[threadId] ?? codexLatestTurnIds[sessionId] else {
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
            withAnimation(NotchAnimation.open) {
                surface = .sessionList
            }
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
                    log.error("Codex continue failed for \(threadId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self?.sessions[sessionId]?.status = .idle
                    self?.refreshDerivedState()
                }
            }
        }
    }

    @discardableResult
    func focusSession(sessionId: String) -> Bool {
        guard sessions[sessionId] != nil else { return false }
        acknowledgePendingCompletionReview(for: sessionId)
        activeSessionId = sessionId
        withAnimation(NotchAnimation.open) {
            surface = .sessionList
        }
        startRotationIfNeeded()
        refreshDerivedState()
        return true
    }

    func jumpToSession(_ sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        acknowledgePendingCompletionReview(for: sessionId)
        SessionJumpRouter.jump(to: session, sessionId: sessionId)
    }

    func needsCompletionReview(sessionId: String) -> Bool {
        pendingCompletionReviewSessionIds.contains(sessionId)
    }

    @discardableResult
    func focusSession(cwd: String?, source: String?) -> String? {
        let normalizedCwd = nonEmpty(cwd)
        let normalizedSource = nonEmpty(source)?.lowercased()

        let match = sessions
            .filter { _, session in
                let cwdMatches = normalizedCwd == nil || session.cwd == normalizedCwd
                let sourceMatches = normalizedSource == nil || session.source == normalizedSource
                return cwdMatches && sourceMatches
            }
            .max { lhs, rhs in
                lhs.value.lastActivity < rhs.value.lastActivity
            }?.key

        guard let match, focusSession(sessionId: match) else { return nil }
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
        let groups: [SessionListGroupPresentation]

        switch groupingMode {
        case "project":
            var projectGroups: [String: [String]] = [:]
            for id in allIds {
                let project = sessions[id]?.displayName ?? "Session"
                projectGroups[project, default: []].append(id)
            }

            let sortedProjects = projectGroups.keys.sorted { lhs, rhs in
                latestActivity(for: projectGroups[lhs] ?? []) > latestActivity(for: projectGroups[rhs] ?? [])
            }

            groups = sortedProjects.enumerated().map { index, project in
                let ids = sortedSessionIDsByActivity(projectGroups[project] ?? [])
                return SessionListGroupPresentation(
                    id: "project-\(index)-\(project)",
                    header: "\(project) (\(ids.count))",
                    source: nil,
                    ids: ids
                )
            }

        case "status":
            let l10n = L10n.shared
            let statusGroups: [(Set<AgentStatus>, String)] = [
                ([.running], l10n["status_running"]),
                ([.waitingApproval, .waitingQuestion], l10n["status_waiting"]),
                ([.processing], l10n["status_processing"]),
                ([.idle], l10n["status_idle"]),
            ]

            groups = statusGroups.enumerated().compactMap { index, item in
                let (statuses, label) = item
                let ids = sortedSessionIDsByActivity(allIds.filter { id in
                    guard let session = sessions[id] else { return false }
                    return statuses.contains(session.status)
                })
                guard !ids.isEmpty else { return nil }
                return SessionListGroupPresentation(
                    id: "status-\(index)-\(label)",
                    header: "\(label) (\(ids.count))",
                    source: nil,
                    ids: ids
                )
            }

        case "cli":
            let cliOrder: [(source: String, name: String)] = [
                ("claude", "Claude"),
                ("codex", "Codex"),
                ("gemini", "Gemini"),
                ("cursor", "Cursor"),
                ("copilot", "Copilot"),
                ("qoder", "Qoder"),
                ("droid", "Factory"),
                ("codebuddy", "CodeBuddy"),
                ("opencode", "OpenCode"),
            ]

            var result: [SessionListGroupPresentation] = []
            var seen = Set<String>()

            for (index, cli) in cliOrder.enumerated() {
                let ids = sortedSessionIDsByActivity(allIds.filter { id in
                    sessions[id]?.source == cli.source
                })
                guard !ids.isEmpty else { continue }
                ids.forEach { seen.insert($0) }
                result.append(
                    SessionListGroupPresentation(
                        id: "cli-\(index)-\(cli.source)",
                        header: "\(cli.name) (\(ids.count))",
                        source: cli.source,
                        ids: ids
                    )
                )
            }

            let remaining = sortedSessionIDsByActivity(allIds.filter { !seen.contains($0) })
            if !remaining.isEmpty {
                result.append(
                    SessionListGroupPresentation(
                        id: "cli-other",
                        header: "\(L10n.shared["other"]) (\(remaining.count))",
                        source: nil,
                        ids: remaining
                    )
                )
            }
            groups = result

        default:
            let sorted = sortedSessionIDsByActivity(allIds)
            groups = [
                SessionListGroupPresentation(
                    id: "all",
                    header: "",
                    source: nil,
                    ids: sorted
                )
            ]
        }

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
    private func refreshDerivedState() {
        let summary = deriveSessionSummary(from: sessions)
        var didChange = false
        // Only assign when changed (avoids unnecessary @Observable notifications)
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

    private func invalidateSessionListPresentationCache() {
        sessionListCacheRevision &+= 1
        cachedSessionListPresentations.removeAll(keepingCapacity: true)
    }

    private func notifyPanelStateChanged() {
        NotificationCenter.default.post(name: .superIslandPanelStateDidChange, object: self)
    }

    private func refreshProviderTitle(for trackedSessionId: String, providerSessionId: String? = nil) {
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
            withAnimation(NotchAnimation.open) {
                surface = .sessionList
            }
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
            withAnimation(NotchAnimation.close) {
                surface = sessions.isEmpty ? .collapsed : .sessionList
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
        surface = .collapsed
        codexLatestTurnIds.removeAll()

        SessionPersistence.clear()
        sessionTerminalIndexStore.clear()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.historicalSessionsClearedAtKey)

        refreshDerivedState()
    }

    private func handleCodexPermissionNotification(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let threadId = userInfo["threadId"] as? String,
              let toolName = userInfo["toolName"] as? String else { return }

        let prompt = nonEmpty(userInfo["prompt"] as? String)
        let stringToolInput = userInfo["toolInput"] as? [String: String]
        let toolInput = stringToolInput?.reduce(into: [String: Any]()) { partial, entry in
            partial[entry.key] = entry.value
        }
        var rawJSON: [String: Any] = ["_source": "codex"]
        if let prompt {
            rawJSON["message"] = prompt
        }
        if let cwd = nonEmpty(stringToolInput?["cwd"]) {
            rawJSON["cwd"] = cwd
        }

        let event = HookEvent(
            eventName: "PermissionRequest",
            sessionId: threadId,
            toolName: toolName,
            toolInput: toolInput,
            rawJSON: rawJSON
        )

        let request = PermissionRequest(
            event: event,
            approveAction: { [weak self] always in
                Task {
                    await CodexAppServerClient.shared.approve(threadId: threadId, forSession: always)
                    await MainActor.run {
                        guard let self else { return }
                        self.requestCodexRefresh(minimumInterval: 0)
                    }
                }
            },
            denyAction: { [weak self] in
                Task {
                    await CodexAppServerClient.shared.deny(threadId: threadId)
                    await MainActor.run {
                        guard let self else { return }
                        self.requestCodexRefresh(minimumInterval: 0)
                    }
                }
            }
        )

        enqueueCodexPermissionRequest(request, event: event, sessionId: threadId)
    }

    private func handleCodexQuestionNotification(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let threadId = userInfo["threadId"] as? String,
              let prompt = userInfo["prompt"] as? String else { return }

        let options = userInfo["options"] as? [String]
        let descriptions = userInfo["descriptions"] as? [String]
        let header = nonEmpty(userInfo["header"] as? String)
        var toolInput: [String: Any] = ["question": prompt]
        if let options {
            toolInput["options"] = options
        }
        if let header {
            toolInput["header"] = header
        }
        var rawJSON: [String: Any] = [
            "_source": "codex",
            "question": prompt,
        ]
        if let options {
            rawJSON["options"] = options
        }

        let event = HookEvent(
            eventName: "AskUserQuestion",
            sessionId: threadId,
            toolName: "requestUserInput",
            toolInput: toolInput,
            rawJSON: rawJSON
        )
        let payload = QuestionPayload(
            question: prompt,
            options: options,
            descriptions: descriptions,
            header: header
        )

        let request = QuestionRequest(
            event: event,
            question: payload,
            isFromPermission: false,
            answerAction: { [weak self] answer in
                Task {
                    await CodexAppServerClient.shared.answer(threadId: threadId, answer: answer)
                    await MainActor.run {
                        guard let self else { return }
                        self.requestCodexRefresh(minimumInterval: 0)
                    }
                }
            },
            skipAction: { [weak self] in
                Task {
                    await CodexAppServerClient.shared.skipQuestion(threadId: threadId)
                    await MainActor.run {
                        guard let self else { return }
                        self.requestCodexRefresh(minimumInterval: 0)
                    }
                }
            }
        )

        enqueueCodexQuestionRequest(request, event: event, sessionId: threadId)
    }

    private func handleCodexRefreshNotification(_ note: Notification) {
        let threadId = nonEmpty(note.userInfo?["threadId"] as? String)
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

    private func enqueueCodexPermissionRequest(_ request: PermissionRequest, event: HookEvent, sessionId: String) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }

        let codexPermissionCwd = sessions[sessionId]?.cwd ?? nonEmpty(event.rawJSON["cwd"] as? String)
        sessions[sessionId]?.source = "codex"
        sessions[sessionId]?.providerSessionId = sessionId
        sessions[sessionId]?.cwd = codexPermissionCwd
        sessions[sessionId]?.status = .waitingApproval
        sessions[sessionId]?.currentTool = event.toolName
        sessions[sessionId]?.toolDescription = event.toolDescription
        sessions[sessionId]?.lastActivity = Date()

        drainQuestions(forSession: sessionId)
        drainPermissions(forSession: sessionId)
        permissionQueue.append(request)

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        activeSessionId = sessionId
        surface = .approvalCard(sessionId: sessionId)
        SoundManager.shared.handleEvent("PermissionRequest")
        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
    }

    private func enqueueCodexQuestionRequest(_ request: QuestionRequest, event: HookEvent, sessionId: String) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }

        let codexQuestionCwd = sessions[sessionId]?.cwd ?? nonEmpty(event.rawJSON["cwd"] as? String)
        sessions[sessionId]?.source = "codex"
        sessions[sessionId]?.providerSessionId = sessionId
        sessions[sessionId]?.cwd = codexQuestionCwd
        sessions[sessionId]?.status = .waitingQuestion
        sessions[sessionId]?.lastActivity = Date()

        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)
        questionQueue.append(request)

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        activeSessionId = sessionId
        withAnimation(NotchAnimation.open) {
            surface = .questionCard(sessionId: sessionId)
        }
        SoundManager.shared.handleEvent("PermissionRequest")
        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
    }

    func handleEvent(_ event: HookEvent) {
        // Skip events from subagent worktrees — tracked via parent's SubagentStart/Stop
        if let cwd = event.rawJSON["cwd"] as? String,
           cwd.contains("/.claude/worktrees/agent-") || cwd.contains("/.git/worktrees/agent-") {
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

        // Skip Codex APP internal sessions (title generation, etc.) — they have no transcript
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

        // Model transcript read: done AFTER reduceEvent so extractMetadata has filled in cwd
        if sessions[sessionId]?.model == nil && !modelReadAttempted.contains(sessionId) {
            modelReadAttempted.insert(sessionId)
            let cwd = sessions[sessionId]?.cwd
            let model = Self.readModelFromTranscript(sessionId: sessionId, cwd: cwd)
            sessions[sessionId]?.model = model
        }

        // If session was waiting but received an activity event, the question/permission
        // was answered externally (e.g. user replied in terminal). Clear pending items.
        if wasWaiting {
            let en = normalizedEventName
            // Events that should NOT clear waiting state
            let keepWaiting: Set<String> = ["Notification", "SessionStart", "SessionEnd", "PreCompact"]
            if !keepWaiting.contains(en) {
                drainPermissions(forSession: sessionId)
                drainQuestions(forSession: sessionId)
                if sessions[sessionId]?.status == .waitingApproval
                    || sessions[sessionId]?.status == .waitingQuestion {
                    sessions[sessionId]?.status = (en == "Stop") ? .idle : .processing
                    sessions[sessionId]?.currentTool = nil
                    sessions[sessionId]?.toolDescription = nil
                }
                showNextPending()
            }
        }

        // Detect Cursor YOLO mode once per session (nil = unchecked)
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

        // Keep activeSessionId reserved for genuinely active sessions.
        if sessions[sessionId]?.status == .idle && activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }

        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
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

    private func markPendingCompletionReview(for sessionId: String) {
        guard sessions[sessionId] != nil else { return }
        pendingCompletionReviewSessionIds.insert(sessionId)
    }

    private func acknowledgePendingCompletionReview(for sessionId: String) {
        pendingCompletionReviewSessionIds.remove(sessionId)
    }

    func handlePermissionRequest(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        // Extract metadata so blocking-first sessions have cwd, source, cliPid, terminal info
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        tryMonitorSession(sessionId)
        acknowledgePendingCompletionReview(for: sessionId)

        // Clear any pending questions for THIS session (mutually exclusive within a session)
        drainQuestions(forSession: sessionId)

        sessions[sessionId]?.status = .waitingApproval
        sessions[sessionId]?.currentTool = event.toolName
        sessions[sessionId]?.toolDescription = event.toolDescription
        sessions[sessionId]?.lastActivity = Date()

        let request = PermissionRequest(event: event, continuation: continuation)
        permissionQueue.append(request)

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        // Show UI only if this is the first (or only) queued item
        if permissionQueue.count == 1 {
            activeSessionId = sessionId
            surface = .approvalCard(sessionId: sessionId)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
    }

    func approvePermission(always: Bool = false) {
        guard !permissionQueue.isEmpty else { return }
        let pending = permissionQueue.removeFirst()
        if let approveAction = pending.approveAction {
            approveAction(always)
        } else {
            let responseData: Data
            if always {
                let toolName = pending.event.toolName ?? ""
                let obj: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "allow",
                            "updatedPermissions": [[
                                "type": "addRules",
                                "rules": [["toolName": toolName, "ruleContent": "*"]],
                                "behavior": "allow",
                                "destination": "session",
                            ]],
                        ] as [String: Any],
                    ] as [String: Any],
                ]
                responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            } else {
                let response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
                responseData = Data(response.utf8)
            }
            pending.continuation?.resume(returning: responseData)
        }
        let sessionId = pending.event.sessionId ?? "default"
        let nextStatus: AgentStatus = sessions[sessionId]?.source == "codex" ? .processing : .running
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
            let response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
            pending.continuation?.resume(returning: Data(response.utf8))
        }
        let sessionId = pending.event.sessionId ?? "default"
        let nextStatus: AgentStatus = sessions[sessionId]?.source == "codex" ? .processing : .idle
        sessions[sessionId]?.status = nextStatus
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil

        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }

        showNextPending()
        refreshDerivedState()
    }

    func handleQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        tryMonitorSession(sessionId)
        acknowledgePendingCompletionReview(for: sessionId)

        guard let question = QuestionPayload.from(event: event) else {
            continuation.resume(returning: Data("{}".utf8))
            return
        }
        drainPermissions(forSession: sessionId)

        sessions[sessionId]?.status = .waitingQuestion
        sessions[sessionId]?.lastActivity = Date()

        let request = QuestionRequest(event: event, question: question, continuation: continuation)
        questionQueue.append(request)

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        if questionQueue.count == 1 {
            activeSessionId = sessionId
            withAnimation(NotchAnimation.open) {
                surface = .questionCard(sessionId: sessionId)
            }
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
    }

    func handleAskUserQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        tryMonitorSession(sessionId)
        acknowledgePendingCompletionReview(for: sessionId)

        let payload: QuestionPayload
        if let questions = event.toolInput?["questions"] as? [[String: Any]],
           let first = questions.first {
            let questionText = first["question"] as? String ?? "Question"
            let header = first["header"] as? String
            var optionLabels: [String]?
            var optionDescs: [String]?
            if let opts = first["options"] as? [[String: Any]] {
                optionLabels = opts.compactMap { $0["label"] as? String }
                optionDescs = opts.compactMap { $0["description"] as? String }
            }
            payload = QuestionPayload(question: questionText, options: optionLabels, descriptions: optionDescs, header: header)
        } else {
            let questionText = event.toolInput?["question"] as? String ?? "Question"
            var options: [String]?
            if let stringOpts = event.toolInput?["options"] as? [String] {
                options = stringOpts
            } else if let dictOpts = event.toolInput?["options"] as? [[String: Any]] {
                options = dictOpts.compactMap { $0["label"] as? String }
            }
            payload = QuestionPayload(question: questionText, options: options)
        }

        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)

        sessions[sessionId]?.status = .waitingQuestion
        sessions[sessionId]?.lastActivity = Date()

        let request = QuestionRequest(event: event, question: payload, continuation: continuation, isFromPermission: true)
        questionQueue.append(request)

        if sessions[sessionId] != nil {
            scheduleTerminalIndexPersist(sessionId: sessionId)
        }

        if questionQueue.count == 1 {
            activeSessionId = sessionId
            withAnimation(NotchAnimation.open) {
                surface = .questionCard(sessionId: sessionId)
            }
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
    }

    func answerQuestion(_ answer: String) {
        guard !questionQueue.isEmpty else { return }
        let pending = questionQueue.removeFirst()
        if let answerAction = pending.answerAction {
            answerAction(answer)
        } else {
            let responseData: Data
            if pending.isFromPermission {
                let answerKey = pending.question.header ?? "answer"
                let obj: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "allow",
                            "updatedInput": [
                                "answers": [answerKey: answer],
                            ],
                        ] as [String: Any],
                    ] as [String: Any],
                ]
                responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            } else {
                let obj: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "Notification",
                        "answer": answer,
                    ] as [String: Any],
                ]
                responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            }
            pending.continuation?.resume(returning: responseData)
        }
        let sessionId = pending.event.sessionId ?? "default"
        sessions[sessionId]?.status = .processing

        showNextPending()
        refreshDerivedState()
    }

    func skipQuestion() {
        guard !questionQueue.isEmpty else { return }
        let pending = questionQueue.removeFirst()
        if let skipAction = pending.skipAction {
            skipAction()
        } else {
            let responseData: Data
            if pending.isFromPermission {
                responseData = Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#.utf8)
            } else {
                responseData = Data(#"{"hookSpecificOutput":{"hookEventName":"Notification"}}"#.utf8)
            }
            pending.continuation?.resume(returning: responseData)
        }
        let sessionId = pending.event.sessionId ?? "default"
        sessions[sessionId]?.status = .processing

        showNextPending()
        refreshDerivedState()
    }

    /// Drain all queued permissions for a specific session, resuming their continuations with deny
    private func drainPermissions(forSession sessionId: String) {
        let denyResponse = Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#.utf8)
        permissionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            if let denyAction = item.denyAction {
                denyAction()
            } else {
                item.continuation?.resume(returning: denyResponse)
            }
            return true
        }
    }

    /// Called when the bridge socket disconnects — the question/permission was answered externally (e.g. user replied in terminal)
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

    /// Drain all queued questions for a specific session, resuming their continuations with empty
    private func drainQuestions(forSession sessionId: String) {
        questionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            if let skipAction = item.skipAction {
                skipAction()
            } else {
                item.continuation?.resume(returning: Data("{}".utf8))
            }
            return true
        }
    }

    /// After dequeuing, show next pending item or collapse
    private func showNextPending() {
        if let next = permissionQueue.first {
            let sid = next.event.sessionId ?? "default"
            activeSessionId = sid
            surface = .approvalCard(sessionId: sid)
        } else if let next = questionQueue.first {
            let sid = next.event.sessionId ?? "default"
            activeSessionId = sid
            surface = .questionCard(sessionId: sid)
        } else if case .approvalCard = surface {
            surface = .collapsed
        } else if case .questionCard = surface {
            surface = .collapsed
        }
    }

    /// Find the most recently active non-idle session.
    private func mostActiveSessionId() -> String? {
        var bestNonIdle: (key: String, time: Date)?
        for (key, session) in sessions {
            if session.status != .idle, bestNonIdle == nil || session.lastActivity > bestNonIdle!.time {
                bestNonIdle = (key, session.lastActivity)
            }
        }
        return bestNonIdle?.key
    }

    /// Check if Cursor is in YOLO mode by reading its settings
    private static func detectCursorYoloMode() -> Bool {
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

    /// Read model from session transcript file
    private static func readModelFromTranscript(sessionId: String, cwd: String?) -> String? {
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

    // MARK: - Session Discovery (FSEventStream + process scan)

    /// Start continuous monitoring: initial process scan + FSEventStream on ~/.claude/projects/
    // MARK: - Session Persistence

    private func scheduleSave() {
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
        // Run one cleanup pass immediately after restoring startup state so stale
        // sessions do not linger until the first 60s timer tick.
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
        // Keep a fresh startup snapshot on disk so a restore-only run does not
        // erase the next launch's session list.
        // Guard against writing an empty file when cleanup removed all restored sessions.
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

    private func attachRestoredProcessMonitorIfNeeded(sessionId: String, snapshot: SessionSnapshot) {
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

    func startSessionDiscovery() {
        Self.debugLog("startSessionDiscovery: entering")
        startCleanupTimer()
        startCodexRefreshLoop()
        // Restore persisted state and historical Codex sessions off the main thread.
        Task.detached(priority: .utility) {
            let persisted = SessionPersistence.load()
            let historicalCodexSessions = ConfigInstaller.isEnabled(source: "codex")
                ? CodexSessionHistoryLoader.loadRecentSessions()
                : []
            Self.debugLog("startSessionDiscovery: loaded persisted=\(persisted.count), historicalCodex=\(historicalCodexSessions.count)")
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.restoreStartupSessions(
                    persisted: persisted,
                    historicalCodexSessions: historicalCodexSessions
                )
            }
        }

        // Initial scan for already-running sessions (Claude + Codex), respecting user toggles
        Task.detached {
            let claudeSessions = ConfigInstaller.isEnabled(source: "claude") ? Self.findActiveClaudeSessions() : []
            let codexSessions = ConfigInstaller.isEnabled(source: "codex") ? Self.findActiveCodexSessions() : []
            await MainActor.run { [weak self] in
                self?.integrateDiscovered(claudeSessions)
                self?.integrateDiscovered(codexSessions)
            }
        }
        // Start watching ~/.claude/projects/ for new session files
        startProjectsWatcher()
    }

    /// FSEventStream on ~/.claude/projects/ — fires when .jsonl files are created/modified
    private func startProjectsWatcher() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsPath = "\(home)/.claude/projects"
        guard FileManager.default.fileExists(atPath: projectsPath) else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let appState = Unmanaged<AppState>.fromOpaque(info).takeUnretainedValue()
                // Debounce: re-scan Claude processes on filesystem change
                appState.handleProjectsDirChange()
            },
            &context,
            [projectsPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,  // 2-second latency (coalesces rapid writes)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.fsEventStream = stream
        log.info("Projects watcher started on \(projectsPath)")
    }

    /// Called by FSEventStream when ~/.claude/projects/ changes (nonisolated for C callback compatibility)
    nonisolated private func handleProjectsDirChange() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Debounce: skip if scanned within the last 3 seconds
            guard Date().timeIntervalSince(self.lastFSScanTime) > 3 else { return }
            self.lastFSScanTime = Date()
            Task.detached {
                let claudeSessions = ConfigInstaller.isEnabled(source: "claude") ? Self.findActiveClaudeSessions() : []
                let codexSessions = ConfigInstaller.isEnabled(source: "codex") ? Self.findActiveCodexSessions() : []
                await MainActor.run { [weak self] in
                    self?.integrateDiscovered(claudeSessions)
                    self?.integrateDiscovered(codexSessions)
                }
            }
        }
    }

    /// Merge discovered sessions into current state (skip already-known ones)
    private func integrateDiscovered(_ discovered: [DiscoveredSession]) {
        var didAdd = false
        var discoveredCodex = false
        for info in discovered {
            if info.source == "codex" {
                discoveredCodex = true
            }
            if SessionFilter.shouldIgnoreSession(source: info.source, cwd: info.cwd, termBundleId: nil) {
                continue
            }
            // Session already known — try to attach PID monitor if missing
            if sessions[info.sessionId] != nil {
                if processMonitors[info.sessionId] == nil, let pid = info.pid {
                    monitorProcess(sessionId: info.sessionId, pid: pid)
                    // Don't mark as processing — process being alive doesn't mean AI is working.
                    // Status will be updated when the next hook event arrives.
                }
                refreshProviderTitle(for: info.sessionId, providerSessionId: info.sessionId)
                continue
            }

            // Dedup: if a hook-created session already exists with same source + cwd + pid,
            // skip the discovered one to avoid duplicate entries (e.g. Codex hooks vs
            // file-based discovery produce different session IDs for the same process).
            // Only dedup when PID matches (or discovered has no PID), so concurrent
            // sessions in the same repo aren't incorrectly merged.
            let duplicateKey = sessions.first(where: { (_, existing) in
                guard existing.source == info.source,
                      existing.cwd != nil, existing.cwd == info.cwd else { return false }
                // If we have PIDs for both, they must match
                if let discoveredPid = info.pid, let existingPid = existing.cliPid,
                   discoveredPid != existingPid { return false }
                return true
            })?.key

            if let existingKey = duplicateKey {
                // Still attach PID monitor to the existing session if missing
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
        codexRefreshTask?.cancel()
        codexRefreshTask = nil
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
        for key in Array(processMonitors.keys) { stopMonitor(key) }
    }

    deinit {
        MainActor.assumeIsolated {
            codexRefreshTask?.cancel()
            terminalIndexFlushTask?.cancel()
            rotationTimer?.invalidate()
            cleanupTimer?.invalidate()
            saveTimer?.invalidate()
            if let usageSnapshotObserver {
                NotificationCenter.default.removeObserver(usageSnapshotObserver)
            }
            if let codexPermissionObserver {
                NotificationCenter.default.removeObserver(codexPermissionObserver)
            }
            if let codexQuestionObserver {
                NotificationCenter.default.removeObserver(codexQuestionObserver)
            }
            if let codexRefreshObserver {
                NotificationCenter.default.removeObserver(codexRefreshObserver)
            }
            if let stream = fsEventStream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            for (_, m) in processMonitors { m.source.cancel() }
        }
    }

    private func startCodexRefreshLoop() {
        codexRefreshTask?.cancel()
        codexRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCodexThreadSnapshots()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await self.refreshCodexThreadSnapshots()
            }
        }
    }

    private func requestCodexRefresh(minimumInterval: TimeInterval) {
        guard Date().timeIntervalSince(lastCodexRefreshAt) >= minimumInterval else { return }
        guard !codexRefreshInFlight else { return }
        Task { [weak self] in
            await self?.refreshCodexThreadSnapshots()
        }
    }

    private func refreshCodexThreadSnapshots() async {
        guard ConfigInstaller.isEnabled(source: "codex") else { return }
        let threadIds = trackedCodexThreadIds()
        guard !threadIds.isEmpty else { return }
        guard !codexRefreshInFlight else { return }

        codexRefreshInFlight = true
        defer {
            codexRefreshInFlight = false
            lastCodexRefreshAt = Date()
        }

        var didChange = false
        for threadId in threadIds.prefix(8) {
            guard sessions.values.contains(where: { $0.source == "codex" }) else { break }
            do {
                let snapshot = try await CodexAppServerClient.shared.readThread(threadId: threadId)
                didChange = applyCodexThreadSnapshot(snapshot) || didChange
            } catch {
                log.debug("Codex app-server refresh failed for \(threadId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if didChange {
            scheduleSave()
            startRotationIfNeeded()
            refreshDerivedState()
        }
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
            codexLatestTurnIds[snapshot.threadId] = latestTurnId
            codexLatestTurnIds[trackedSessionId] = latestTurnId
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

    private func trackedSessionId(forCodexThreadId threadId: String, cwd: String?) -> String? {
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

    private struct DiscoveredSession {
        let sessionId: String
        let cwd: String
        let tty: String?
        let model: String?
        let pid: pid_t?
        let modifiedAt: Date
        let recentMessages: [ChatMessage]
        var source: String = "claude"  // "claude" or "codex"
    }

    /// Find running `claude` processes, match to transcript files, extract recent messages
    private nonisolated static func findActiveClaudeSessions() -> [DiscoveredSession] {
        // Step 1: find running claude processes using native APIs
        let claudePids = findClaudePids()
        guard !claudePids.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        var results: [DiscoveredSession] = []
        var seenSessionIds: Set<String> = []

        // Each claude process → its CWD → the single most recent .jsonl
        for pid in claudePids {
            guard let cwd = getCwd(for: pid), !cwd.isEmpty else { continue }

            // Skip subagent worktrees — they are child tasks, not independent sessions
            if cwd.contains("/.claude/worktrees/agent-") || cwd.contains("/.git/worktrees/agent-") {
                continue
            }

            if SessionFilter.shouldIgnoreSession(source: "claude", cwd: cwd, termBundleId: nil) {
                continue
            }

            // Get process start time to filter stale transcript files
            let processStart = getProcessStartTime(pid)

            let projectDir = cwd.claudeProjectDirEncoded()
            let projectPath = "\(home)/.claude/projects/\(projectDir)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }

            // Find the most recently modified .jsonl that was written AFTER this process started
            var bestFile: String?
            var bestDate = Date.distantPast
            for file in files where file.hasSuffix(".jsonl") {
                let fullPath = "\(projectPath)/\(file)"
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified > bestDate {
                    // Skip files from old sessions: must be modified after process started
                    if let start = processStart, modified < start.addingTimeInterval(-10) {
                        continue
                    }
                    bestDate = modified
                    bestFile = file
                }
            }

            guard let file = bestFile else { continue }

            // Skip stale transcripts: only show sessions active within last 5 minutes
            // This filters out orphaned processes (terminal closed but process survived)
            if bestDate.timeIntervalSinceNow < -300 { continue }

            let sessionId = String(file.dropLast(6))
            guard !seenSessionIds.contains(sessionId) else { continue }
            seenSessionIds.insert(sessionId)

            let (model, messages) = readRecentFromTranscript(path: "\(projectPath)/\(file)")

            results.append(DiscoveredSession(
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                model: model,
                pid: pid,
                modifiedAt: bestDate,
                recentMessages: messages
            ))
        }
        return results
    }

    /// Get PIDs of running Claude Code processes
    /// Claude's binary is named by version (e.g. "2.1.91") under ~/.local/share/claude/versions/
    private nonisolated static func findClaudePids() -> [pid_t] {
        var bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size + 10)
        bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let count = Int(bufferSize) / MemoryLayout<pid_t>.size

        let claudeVersionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions").path

        var claudePids: [pid_t] = []
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard len > 0 else { continue }
            let path = String(cString: pathBuffer)
            // Match processes whose executable is under claude's versions directory
            if path.hasPrefix(claudeVersionsDir) {
                claudePids.append(pid)
            }
        }
        return claudePids
    }

    /// Get the current working directory of a process using proc_pidinfo
    private nonisolated static func getCwd(for pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
        guard ret > 0 else { return nil }
        return withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// Get the start time of a process using proc_pidinfo
    private nonisolated static func getProcessStartTime(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    // MARK: - Codex Session Discovery

    /// Find running Codex processes.
    /// Checks both executable path (Desktop app) and command-line args (npm/Homebrew: node script).
    private nonisolated static func findCodexPids() -> [pid_t] {
        var bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size + 10)
        bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let count = Int(bufferSize) / MemoryLayout<pid_t>.size

        var codexPids: [pid_t] = []
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard len > 0 else { continue }
            let path = String(cString: pathBuffer)
            let pathLower = path.lowercased()

            // Match 1: Codex Desktop app (native binary)
            if pathLower.contains("codex.app/contents/") && pathLower.hasSuffix("/codex") {
                codexPids.append(pid)
                continue
            }

            // Match 2: npm/Homebrew install — node running @openai/codex script.
            // proc_pidpath returns the node binary, so check command-line args instead.
            if pathLower.hasSuffix("/node") {
                if let args = getProcessArgs(pid),
                   args.contains(where: { $0.contains("@openai/codex") || $0.contains("openai-codex") }) {
                    codexPids.append(pid)
                }
            }
        }
        return codexPids
    }

    /// Get command-line arguments for a process via sysctl KERN_PROCARGS2.
    private nonisolated static func getProcessArgs(_ pid: pid_t) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // First 4 bytes = argc (as int32)
        guard size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0, argc < 256 else { return nil }

        // Skip past argc + executable path + padding nulls to reach argv
        var offset = MemoryLayout<Int32>.size
        // Skip executable path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null padding
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Parse null-terminated argv strings
        var args: [String] = []
        var argStart = offset
        for _ in 0..<argc {
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if offset > argStart {
                args.append(String(bytes: buffer[argStart..<offset], encoding: .utf8) ?? "")
            }
            offset += 1
            argStart = offset
        }
        return args
    }

    /// Find active Codex sessions by matching running processes to session files
    private nonisolated static func findActiveCodexSessions() -> [DiscoveredSession] {
        let codexPids = findCodexPids()
        guard !codexPids.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        let sessionsBase = "\(home)/.codex/sessions"
        guard fm.fileExists(atPath: sessionsBase) else { return [] }

        var results: [DiscoveredSession] = []
        var seenSessionIds: Set<String> = []

        for pid in codexPids {
            guard let cwd = getCwd(for: pid), !cwd.isEmpty else {
                // getCwd failed
                continue
            }
            // pid found
            let processStart = getProcessStartTime(pid)

            // Codex stores sessions in date-based dirs: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
            // Scan recent directories for matching session files
            guard let bestFile = findRecentCodexSession(base: sessionsBase, cwd: cwd, after: processStart, fm: fm) else {
                // no session file found
                continue
            }

            // Extract session ID from filename: rollout-{date}-{uuid}.jsonl
            let fileName = (bestFile as NSString).lastPathComponent
            let sessionId = extractCodexSessionId(from: fileName)
            guard !sessionId.isEmpty, !seenSessionIds.contains(sessionId) else { continue }
            seenSessionIds.insert(sessionId)

            let modifiedAt = (try? fm.attributesOfItem(atPath: bestFile))?[.modificationDate] as? Date ?? Date()

            // Skip stale transcripts (same as Claude: 5 min freshness filter)
            if modifiedAt.timeIntervalSinceNow < -300 { continue }

            let (model, messages) = readRecentFromCodexTranscript(path: bestFile)

            results.append(DiscoveredSession(
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                model: model,
                pid: pid,
                modifiedAt: modifiedAt,
                recentMessages: messages,
                source: "codex"
            ))
        }
        return results
    }

    /// Find the most recent Codex session file matching a CWD
    /// Scans back up to 7 days to cover long-running sessions that span day boundaries
    private nonisolated static func findRecentCodexSession(base: String, cwd: String, after: Date?, fm: FileManager) -> String? {
        let cal = Calendar.current
        let now = Date()
        var dirs: [String] = []
        for daysBack in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            let y = String(format: "%04d", cal.component(.year, from: date))
            let m = String(format: "%02d", cal.component(.month, from: date))
            let d = String(format: "%02d", cal.component(.day, from: date))
            let dir = "\(base)/\(y)/\(m)/\(d)"
            if fm.fileExists(atPath: dir) {
                dirs.append(dir)
            }
        }
        guard !dirs.isEmpty else { return nil }
        return scanCodexDir(dirs: dirs, cwd: cwd, after: after, fm: fm)
    }

    private nonisolated static func scanCodexDir(dirs: [String], cwd: String, after: Date?, fm: FileManager) -> String? {
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            // Sort descending to check newest first
            let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }.sorted(by: >)

            for file in jsonlFiles.prefix(20) {
                let fullPath = "\(dir)/\(file)"
                if let start = after,
                   let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified < start.addingTimeInterval(-10) {
                    continue
                }
                if codexSessionMatchesCwd(path: fullPath, cwd: cwd) {
                    return fullPath
                }
            }
        }
        return nil
    }

    /// Check if a Codex session file's CWD matches the target
    private nonisolated static func codexSessionMatchesCwd(path: String, cwd: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 4096) // First line is enough
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\n").first,
              let lineData = firstLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let sessionCwd = payload["cwd"] as? String else { return false }
        return sessionCwd == cwd
    }

    /// Extract session ID from Codex filename: rollout-2026-04-04T20-54-48-{uuid}.jsonl
    private nonisolated static func extractCodexSessionId(from filename: String) -> String {
        // Format: rollout-YYYY-MM-DDThh-mm-ss-{uuid}.jsonl
        let name = filename.replacingOccurrences(of: ".jsonl", with: "")
        // The UUID is the last 36 chars (8-4-4-4-12)
        // Pattern: after the datetime portion, everything from the 4th dash group onwards is the UUID
        let parts = name.split(separator: "-")
        // rollout-YYYY-MM-DDThh-mm-ss-{8}-{4}-{4}-{4}-{12}
        // That's: [rollout, YYYY, MM, DDThh, mm, ss, uuid1, uuid2, uuid3, uuid4, uuid5]
        if parts.count >= 11 {
            return parts.suffix(5).joined(separator: "-")
        }
        return name
    }

    /// Read model and recent messages from a Codex transcript file
    private nonisolated static func readRecentFromCodexTranscript(path: String) -> (String?, [ChatMessage]) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, []) }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, []) }

        var model: String?
        var userMessages: [(Int, String)] = []
        var assistantMessages: [(Int, String)] = []
        var index = 0

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""

            // Extract model from session_meta
            if type == "session_meta", model == nil,
               let payload = json["payload"] as? [String: Any] {
                model = payload["model"] as? String
                    ?? payload["model_provider"] as? String
            }

            // Prefer event_msg (cleaner user/agent messages from Codex)
            if type == "event_msg",
               let payload = json["payload"] as? [String: Any],
               let msgType = payload["type"] as? String,
               let msg = payload["message"] as? String, !msg.isEmpty {
                if msgType == "user_message" {
                    userMessages.append((index, msg))
                } else if msgType == "agent_message" {
                    assistantMessages.append((index, msg))
                }
            }

            // Fallback: extract from response_item only if event_msg didn't provide the same content
            // (user messages come from event_msg which is cleaner — response_item user entries
            //  often contain injected system/tool context, not actual user input)
            if type == "response_item",
               let payload = json["payload"] as? [String: Any],
               let role = payload["role"] as? String {

                if let content = payload["content"] as? [[String: Any]] {
                    for item in content {
                        let itemType = item["type"] as? String ?? ""
                        if let t = item["text"] as? String, !t.isEmpty {
                            if role == "user" && itemType == "input_text" && userMessages.isEmpty {
                                // Only use response_item for user messages if no event_msg was found
                                userMessages.append((index, t))
                            } else if role == "assistant" && itemType == "output_text" && assistantMessages.last?.1 != t {
                                // Only add if not a duplicate of the last event_msg entry
                                assistantMessages.append((index, t))
                            }
                            break
                        }
                    }
                }
            }
            index += 1
        }

        var combined: [(Int, ChatMessage)] = []
        for (i, text) in userMessages.suffix(3) {
            combined.append((i, ChatMessage(isUser: true, text: text)))
        }
        for (i, text) in assistantMessages.suffix(3) {
            combined.append((i, ChatMessage(isUser: false, text: text)))
        }
        combined.sort { $0.0 < $1.0 }
        let recent = Array(combined.suffix(3).map { $0.1 })

        return (model, recent)
    }

    /// Read model and last 3 user/assistant messages from a transcript file's tail
    private nonisolated static func readRecentFromTranscript(path: String) -> (String?, [ChatMessage]) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, []) }
        defer { handle.closeFile() }

        // Read last 64KB
        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, []) }

        var model: String?
        var userMessages: [(Int, String)] = []
        var assistantMessages: [(Int, String)] = []
        var index = 0

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String
            else { continue }

            if model == nil, let m = message["model"] as? String, !m.isEmpty {
                model = m
            }

            // Extract text content
            var textContent: String?
            if let content = message["content"] as? String, !content.isEmpty {
                textContent = content
            } else if let contentArray = message["content"] as? [[String: Any]] {
                for item in contentArray {
                    if item["type"] as? String == "text",
                       let t = item["text"] as? String, !t.isEmpty {
                        textContent = t
                        break
                    }
                }
            }

            if let text = textContent {
                if role == "user" {
                    userMessages.append((index, text))
                } else if role == "assistant" {
                    assistantMessages.append((index, text))
                }
            }
            index += 1
        }

        // Build recent messages: take last few user+assistant, sorted by order, keep 3
        var combined: [(Int, ChatMessage)] = []
        for (i, text) in userMessages.suffix(3) {
            combined.append((i, ChatMessage(isUser: true, text: text)))
        }
        for (i, text) in assistantMessages.suffix(3) {
            combined.append((i, ChatMessage(isUser: false, text: text)))
        }
        combined.sort { $0.0 < $1.0 }
        let recent = Array(combined.suffix(3).map { $0.1 })

        return (model, recent)
    }
}

/// Encode a path the same way Claude Code does for project directory names:
/// "/" → "-", non-ASCII → "-", spaces → "-"
extension String {
    func claudeProjectDirEncoded() -> String {
        var result = ""
        for c in self.unicodeScalars {
            if c == "/" || c == " " || c.value > 127 {
                result.append("-")
            } else {
                result.append(Character(c))
            }
        }
        return result
    }
}
