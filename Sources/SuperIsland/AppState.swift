import SwiftUI
import Observation
import SuperIslandCore

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

@MainActor
@Observable
final class AppState {
    static let testingSessionPrefix = AppRuntimeConstants.testingSessionPrefix
    static let historicalSessionsClearedAtKey = "historicalSessionsClearedAt"

    var sessions: [String: SessionSnapshot] = [:] {
        didSet {
            refreshActiveSessionIndex()
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

    var pendingPermission: PermissionRequest? { permissionQueue.first }
    var pendingQuestion: QuestionRequest? { questionQueue.first }
    var previewQuestionPayload: QuestionPayload?
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

    var maxHistory: Int { SettingsManager.shared.maxToolHistory }
    var autoCollapseTask: Task<Void, Never>?
    var completionQueue: [String] = []
    var processMonitors: [String: (source: DispatchSourceProcess, pid: pid_t)] = [:]
    var saveTimer: Timer?
    var terminalIndexFlushTask: Task<Void, Never>?
    var pendingTerminalIndexSessionIds: Set<String> = []
    @ObservationIgnored var pendingDerivedStateRefreshTask: Task<Void, Never>?
    @ObservationIgnored var lastDerivedStateRefreshAt: Date = .distantPast
    let sessionTerminalIndexStore = SessionTerminalIndexStore()
    let codexRefreshService: CodexRefreshService
    let sessionDiscoveryService: SessionDiscoveryService
    private var usageSnapshotObserver: NSObjectProtocol?
    private var codexPermissionObserver: NSObjectProtocol?
    private var codexQuestionObserver: NSObjectProtocol?
    private var codexRefreshObserver: NSObjectProtocol?
    var isShowingCompletion: Bool {
        if case .completionCard = surface { return true }
        return false
    }
    var modelReadAttempted: Set<String> = []
    @ObservationIgnored var sessionListCacheRevision: UInt64 = 0
    @ObservationIgnored var cachedSessionListPresentations: [SessionListCacheKey: CachedSessionListPresentation] = [:]
    var pendingCompletionReviewSessionIds: Set<String> = []

    let minTabVisibilityCheckInterval: TimeInterval = 2.0
    var lastTabVisibilityCheckTime: Date = .distantPast
    var lastTabVisibilityCheckResult: Bool = false

    var activeSessionIdsByActivity: [String] = []
    var rotatingSessionId: String?
    var rotatingSession: SessionSnapshot? {
        guard let rid = rotatingSessionId else { return nil }
        return sessions[rid]
    }
    var rotationTimer: Timer?
    var usageSnapshot: UsageSnapshot = UsageSnapshotStore.load()

    var status: AgentStatus = .idle
    var primarySource: String = "claude"
    var activeSessionCount: Int = 0
    var totalSessionCount: Int = 0

    init() {
        codexRefreshService = CodexRefreshService()
        sessionDiscoveryService = SessionDiscoveryService()

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

    func nonEmpty(_ value: String?) -> String? {
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

    // Tests can create and destroy AppState repeatedly, so explicit cleanup is safer than actor-isolated deinit work.
    func teardown() {
        pendingDerivedStateRefreshTask?.cancel()
        pendingDerivedStateRefreshTask = nil

        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        terminalIndexFlushTask?.cancel()
        terminalIndexFlushTask = nil

        saveTimer?.invalidate()
        saveTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil

        stopSessionDiscovery()

        for sessionId in Array(processMonitors.keys) {
            stopMonitor(sessionId)
        }

        removeObserver(&usageSnapshotObserver)
        removeObserver(&codexPermissionObserver)
        removeObserver(&codexQuestionObserver)
        removeObserver(&codexRefreshObserver)
    }

    private func removeObserver(_ observer: inout NSObjectProtocol?) {
        guard let token = observer else { return }
        NotificationCenter.default.removeObserver(token)
        observer = nil
    }

    deinit {
        // AppState is effectively app-lifetime state in production.
        // Tests should call `teardown()` explicitly because actor-isolated cleanup in deinit is still fragile.
    }
}

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
