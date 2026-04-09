import Foundation
import CodeIslandCore

final class SessionTerminalIndexStore {
    private struct PersistedSessionTerminalRecord: Codable {
        var source: String?
        var cwd: String?
        var sessionTitle: String?
        var lastUserPrompt: String?
        var lastAssistantMessage: String?
        var currentTool: String?
        var toolDescription: String?
        var status: String?
        var lastActivityAt: TimeInterval?
        var termApp: String?
        var itermSessionId: String?
        var ttyPath: String?
        var kittyWindowId: String?
        var tmuxPane: String?
        var tmuxClientTty: String?
        var cmuxWorkspaceRef: String?
        var cmuxSurfaceRef: String?
        var cmuxPaneRef: String?
        var cmuxWorkspaceId: String?
        var cmuxSurfaceId: String?
        var cmuxSocketPath: String?
        var termBundleId: String?

        init(session: SessionSnapshot, existing: PersistedSessionTerminalRecord?) {
            source = session.source.nilIfBlank
            cwd = session.cwd.nilIfBlank
            sessionTitle = session.sessionTitle.nilIfBlank
            lastUserPrompt = session.lastUserPrompt.nilIfBlank ?? existing?.lastUserPrompt
            lastAssistantMessage = session.lastAssistantMessage.nilIfBlank
            currentTool = session.currentTool.nilIfBlank
            toolDescription = session.toolDescription.nilIfBlank
            status = stringStatus(session.status)
            lastActivityAt = session.lastActivity.timeIntervalSince1970
            termApp = session.termApp.nilIfBlank
            itermSessionId = session.itermSessionId.nilIfBlank
            ttyPath = session.ttyPath.nilIfBlank
            kittyWindowId = session.kittyWindowId.nilIfBlank
            tmuxPane = session.tmuxPane.nilIfBlank
            tmuxClientTty = session.tmuxClientTty.nilIfBlank
            cmuxWorkspaceRef = session.cmuxWorkspaceRef.nilIfBlank
            cmuxSurfaceRef = session.cmuxSurfaceRef.nilIfBlank
            cmuxPaneRef = session.cmuxPaneRef.nilIfBlank
            cmuxWorkspaceId = session.cmuxWorkspaceId.nilIfBlank
            cmuxSurfaceId = session.cmuxSurfaceId.nilIfBlank
            cmuxSocketPath = session.cmuxSocketPath.nilIfBlank
            termBundleId = session.termBundleId.nilIfBlank
        }

        var hasUsefulContent: Bool {
            [
                cwd,
                sessionTitle,
                lastUserPrompt,
                lastAssistantMessage,
                currentTool,
                toolDescription,
                termApp,
                itermSessionId,
                ttyPath,
                kittyWindowId,
                tmuxPane,
                tmuxClientTty,
                cmuxWorkspaceRef,
                cmuxSurfaceRef,
                cmuxPaneRef,
                cmuxWorkspaceId,
                cmuxSurfaceId,
                cmuxSocketPath,
                termBundleId,
            ].contains { !($0?.isEmpty ?? true) }
        }

        func applying(to snapshot: SessionSnapshot) -> SessionSnapshot {
            var hydrated = snapshot

            if hydrated.cwd?.nilIfBlank == nil {
                hydrated.cwd = cwd
            }
            if hydrated.sessionTitle?.nilIfBlank == nil {
                hydrated.sessionTitle = sessionTitle
            }
            if hydrated.lastUserPrompt?.nilIfBlank == nil {
                hydrated.lastUserPrompt = lastUserPrompt
            }
            if hydrated.lastAssistantMessage?.nilIfBlank == nil {
                hydrated.lastAssistantMessage = lastAssistantMessage
            }
            if hydrated.currentTool?.nilIfBlank == nil {
                hydrated.currentTool = currentTool
            }
            if hydrated.toolDescription?.nilIfBlank == nil {
                hydrated.toolDescription = toolDescription
            }
            if hydrated.termApp?.nilIfBlank == nil {
                hydrated.termApp = termApp
            }
            if hydrated.itermSessionId?.nilIfBlank == nil {
                hydrated.itermSessionId = itermSessionId
            }
            if hydrated.ttyPath?.nilIfBlank == nil {
                hydrated.ttyPath = ttyPath
            }
            if hydrated.kittyWindowId?.nilIfBlank == nil {
                hydrated.kittyWindowId = kittyWindowId
            }
            if hydrated.tmuxPane?.nilIfBlank == nil {
                hydrated.tmuxPane = tmuxPane
            }
            if hydrated.tmuxClientTty?.nilIfBlank == nil {
                hydrated.tmuxClientTty = tmuxClientTty
            }
            if hydrated.cmuxWorkspaceRef?.nilIfBlank == nil {
                hydrated.cmuxWorkspaceRef = cmuxWorkspaceRef
            }
            if hydrated.cmuxSurfaceRef?.nilIfBlank == nil {
                hydrated.cmuxSurfaceRef = cmuxSurfaceRef
            }
            if hydrated.cmuxPaneRef?.nilIfBlank == nil {
                hydrated.cmuxPaneRef = cmuxPaneRef
            }
            if hydrated.cmuxWorkspaceId?.nilIfBlank == nil {
                hydrated.cmuxWorkspaceId = cmuxWorkspaceId
            }
            if hydrated.cmuxSurfaceId?.nilIfBlank == nil {
                hydrated.cmuxSurfaceId = cmuxSurfaceId
            }
            if hydrated.cmuxSocketPath?.nilIfBlank == nil {
                hydrated.cmuxSocketPath = cmuxSocketPath
            }
            if hydrated.termBundleId?.nilIfBlank == nil {
                hydrated.termBundleId = termBundleId
            }
            if hydrated.source == "claude",
               let persistedSource = source.nilIfBlank,
               let normalizedSource = SessionSnapshot.normalizedSupportedSource(persistedSource) {
                hydrated.source = normalizedSource
            }
            if hydrated.status == .idle,
               let status,
               let decodedStatus = agentStatus(from: status) {
                hydrated.status = decodedStatus
            }
            if let lastActivityAt,
               hydrated.lastActivity == hydrated.startTime || hydrated.lastActivity.timeIntervalSince1970 <= 0 {
                hydrated.lastActivity = Date(timeIntervalSince1970: lastActivityAt)
            }
            if hydrated.recentMessages.isEmpty {
                if let lastUserPrompt {
                    hydrated.addRecentMessage(ChatMessage(isUser: true, text: lastUserPrompt))
                }
                if let lastAssistantMessage {
                    hydrated.addRecentMessage(ChatMessage(isUser: false, text: lastAssistantMessage))
                }
            }

            return hydrated
        }

        private func stringStatus(_ status: AgentStatus) -> String {
            switch status {
            case .idle:
                return "idle"
            case .processing:
                return "processing"
            case .running:
                return "running"
            case .waitingApproval:
                return "waitingApproval"
            case .waitingQuestion:
                return "waitingQuestion"
            }
        }

        private func agentStatus(from raw: String) -> AgentStatus? {
            switch raw {
            case "idle":
                return .idle
            case "processing":
                return .processing
            case "running":
                return .running
            case "waitingApproval":
                return .waitingApproval
            case "waitingQuestion":
                return .waitingQuestion
            default:
                return nil
            }
        }
    }

    private static let maxPersistedSessionCount = 400
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    func hydrate(_ snapshot: SessionSnapshot, sessionId: String) -> SessionSnapshot {
        guard let record = loadRecords()[sessionId] else { return snapshot }
        return record.applying(to: snapshot)
    }

    func persist(sessionId: String, session: SessionSnapshot) {
        persist(sessions: [sessionId: session])
    }

    func persist(sessions: [String: SessionSnapshot]) {
        guard !sessions.isEmpty else { return }

        var records = loadRecords()
        var didChange = false

        for (sessionId, session) in sessions {
            guard !session.isHistoricalSnapshot else { continue }
            guard !SessionFilter.shouldIgnoreSession(source: session.source, cwd: session.cwd, termBundleId: session.termBundleId) else {
                if records.removeValue(forKey: sessionId) != nil {
                    didChange = true
                }
                continue
            }
            let record = PersistedSessionTerminalRecord(session: session, existing: records[sessionId])
            guard record.hasUsefulContent else { continue }
            records[sessionId] = record
            didChange = true
        }

        guard didChange else { return }
        prune(records: &records)
        write(records)
    }

    func clear() {
        guard let url = recordsURL() else { return }
        try? fileManager.removeItem(at: url)
    }

    private func loadRecords() -> [String: PersistedSessionTerminalRecord] {
        guard let url = recordsURL(),
              let data = try? Data(contentsOf: url),
              let records = try? decoder.decode([String: PersistedSessionTerminalRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    private func write(_ records: [String: PersistedSessionTerminalRecord]) {
        guard let url = recordsURL(),
              let data = try? encoder.encode(records) else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private func prune(records: inout [String: PersistedSessionTerminalRecord]) {
        guard records.count > Self.maxPersistedSessionCount else { return }

        let survivors = records
            .sorted { lhs, rhs in
                (lhs.value.lastActivityAt ?? 0) > (rhs.value.lastActivityAt ?? 0)
            }
            .prefix(Self.maxPersistedSessionCount)

        records = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }

    private func recordsURL() -> URL? {
        let baseURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeisland", isDirectory: true)
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("session-terminals.json", isDirectory: false)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let self else { return nil }
        return self.nilIfBlank
    }
}
