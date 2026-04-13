import Foundation
import os.log
import SuperIslandCore

struct CodexAppThreadSnapshot {
    let threadId: String
    let title: String?
    let cwd: String?
    let updatedAt: Date
    let status: AgentStatus
    let latestTurnId: String?
    let lastUserText: String?
    let lastAssistantText: String?
    let recentMessages: [ChatMessage]
}

actor CodexAppServerClient {
    static let shared = CodexAppServerClient()

    private enum PendingRequestKind {
        case commandApproval
        case fileApproval
        case permissionsApproval
        case userInput
    }

    private struct PendingRequest {
        let requestId: String
        let threadId: String
        let kind: PendingRequestKind
        let requestedPermissions: [String: Any]?
        let questionKeys: [String]
    }

    private let logger = Logger(subsystem: "com.superisland", category: "CodexAppServer")
    private let port = 41241

    private var process: Process?
    private var websocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var requestSequence = 0
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pendingRequestsByThread: [String: PendingRequest] = [:]

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        process?.terminate()
        process = nil
        pendingRequestsByThread.removeAll()

        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: CancellationError())
        }
        pendingResponses.removeAll()
    }

    func readThread(threadId: String) async throws -> CodexAppThreadSnapshot {
        if websocket == nil {
            _ = await startIfNeeded()
        }

        let response = try await sendRequest(
            method: "thread/read",
            params: [
                "threadId": threadId,
                "includeTurns": true,
            ]
        )

        guard let thread = response["thread"] as? [String: Any],
              let snapshot = parseThreadSnapshot(threadId: threadId, thread: thread) else {
            throw NSError(domain: "CodexAppServer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid thread/read response",
            ])
        }

        return snapshot
    }

    func approve(threadId: String, forSession: Bool) async {
        guard let pending = pendingRequestsByThread[threadId] else { return }
        let result: [String: Any]

        switch pending.kind {
        case .commandApproval, .fileApproval:
            result = ["decision": forSession ? "acceptForSession" : "accept"]
        case .permissionsApproval:
            result = [
                "permissions": pending.requestedPermissions ?? [:],
                "scope": forSession ? "session" : "turn",
            ]
        case .userInput:
            return
        }

        await sendResponse(id: pending.requestId, result: result)
        pendingRequestsByThread.removeValue(forKey: threadId)
    }

    func deny(threadId: String) async {
        guard let pending = pendingRequestsByThread[threadId] else { return }
        let result: [String: Any]

        switch pending.kind {
        case .commandApproval, .fileApproval:
            result = ["decision": "decline"]
        case .permissionsApproval:
            result = [
                "permissions": [:],
                "scope": "turn",
            ]
        case .userInput:
            return
        }

        await sendResponse(id: pending.requestId, result: result)
        pendingRequestsByThread.removeValue(forKey: threadId)
    }

    func answer(threadId: String, answer: String) async {
        guard let pending = pendingRequestsByThread[threadId], pending.kind == .userInput else { return }
        let key = pending.questionKeys.first ?? "answer"
        await sendResponse(
            id: pending.requestId,
            result: [
                "answers": [
                    key: [
                        "answers": [answer],
                    ],
                ],
            ]
        )
        pendingRequestsByThread.removeValue(forKey: threadId)
    }

    func skipQuestion(threadId: String) async {
        guard let pending = pendingRequestsByThread[threadId], pending.kind == .userInput else { return }
        await sendResponse(id: pending.requestId, result: ["answers": [:]])
        pendingRequestsByThread.removeValue(forKey: threadId)
    }

    func continueThread(threadId: String, expectedTurnId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if websocket == nil {
            _ = await startIfNeeded()
        }

        _ = try await sendRequest(
            method: "turn/steer",
            params: [
                "threadId": threadId,
                "expectedTurnId": expectedTurnId,
                "input": [
                    [
                        "type": "text",
                        "text": trimmed,
                    ],
                ],
            ]
        )
    }

    private func startIfNeeded() async -> Bool {
        if await connectToServer() {
            return true
        }

        guard let executable = resolveCodexExecutable() else {
            logger.notice("Codex executable not found; app-server monitor disabled")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "ws://127.0.0.1:\(port)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            self.process = process
        } catch {
            logger.error("Failed to launch codex app-server: \(error.localizedDescription, privacy: .public)")
            return false
        }

        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if await connectToServer() {
                return true
            }
        }

        logger.error("Unable to connect to codex app-server on port \(self.port)")
        return false
    }

    private func connectToServer() async -> Bool {
        guard websocket == nil else { return true }
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { return false }

        let websocket = URLSession.shared.webSocketTask(with: url)
        websocket.resume()
        self.websocket = websocket

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        do {
            _ = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "SuperIsland",
                        "title": "SuperIsland",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppVersion.fallback,
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                    ],
                ]
            )
            return true
        } catch {
            logger.debug("Codex websocket initialize failed: \(error.localizedDescription, privacy: .public)")
            receiveTask?.cancel()
            receiveTask = nil
            websocket.cancel(with: .goingAway, reason: nil)
            self.websocket = nil
            return false
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let websocket else { return }
            do {
                let message = try await websocket.receive()
                await handle(message)
            } catch {
                logger.debug("Codex websocket closed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let raw):
            data = raw
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let method = json["method"] as? String {
            if let idValue = json["id"] {
                await handleServerRequest(
                    id: String(describing: idValue),
                    method: method,
                    params: json["params"] as? [String: Any] ?? [:]
                )
            } else {
                await handleNotification(method: method, params: json["params"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let idValue = json["id"] else { return }

        let id = String(describing: idValue)
        guard let continuation = pendingResponses.removeValue(forKey: id) else { return }

        if let result = json["result"] as? [String: Any] {
            continuation.resume(returning: result)
        } else if json["result"] is NSNull {
            continuation.resume(returning: [:])
        } else if let errorObject = json["error"] as? [String: Any] {
            let message = (errorObject["message"] as? String) ?? "Unknown Codex app-server error"
            continuation.resume(throwing: NSError(domain: "CodexAppServer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message,
            ]))
        } else {
            continuation.resume(returning: [:])
        }
    }

    private func handleNotification(method: String, params: [String: Any]) async {
        switch method {
        case "thread/name/updated":
            guard let threadId = params["threadId"] as? String else { return }
            await postThreadRefreshRequested(threadId: threadId)
        case "thread/status/changed":
            guard let threadId = params["threadId"] as? String else { return }
            await postThreadRefreshRequested(threadId: threadId)
        case "thread/archived":
            guard let threadId = params["threadId"] as? String else { return }
            pendingRequestsByThread.removeValue(forKey: threadId)
            await postThreadRefreshRequested(threadId: threadId)
        case "thread/started":
            if let threadId = (params["thread"] as? [String: Any])?["id"] as? String {
                await postThreadRefreshRequested(threadId: threadId)
            }
        default:
            break
        }
    }

    private func handleServerRequest(id: String, method: String, params: [String: Any]) async {
        switch method {
        case "item/commandExecution/requestApproval":
            let threadId = (params["threadId"] as? String) ?? (params["conversationId"] as? String) ?? ""
            guard !threadId.isEmpty else { return }
            let command = ((params["command"] as? [String]) ?? []).joined(separator: " ")
            let cwd = sanitizedText(params["cwd"] as? String)
            let reason = sanitizedText(params["reason"] as? String)

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .commandApproval,
                requestedPermissions: nil,
                questionKeys: []
            )

            await postPermissionRequest(
                threadId: threadId,
                toolName: "exec_command",
                prompt: reason ?? command,
                toolInput: [
                    "command": command,
                    "cwd": cwd ?? "",
                ]
            )

        case "item/fileChange/requestApproval":
            guard let threadId = params["threadId"] as? String else { return }
            let grantRoot = sanitizedText(params["grantRoot"] as? String)
            let reason = sanitizedText(params["reason"] as? String)

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .fileApproval,
                requestedPermissions: nil,
                questionKeys: []
            )

            await postPermissionRequest(
                threadId: threadId,
                toolName: "file_change",
                prompt: reason ?? grantRoot ?? "Codex wants to modify files in this workspace.",
                toolInput: [
                    "file_path": grantRoot ?? "",
                ]
            )

        case "item/permissions/requestApproval":
            guard let threadId = params["threadId"] as? String else { return }
            let permissions = params["permissions"] as? [String: Any] ?? [:]
            let reason = sanitizedText(params["reason"] as? String)

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .permissionsApproval,
                requestedPermissions: permissions,
                questionKeys: []
            )

            await postPermissionRequest(
                threadId: threadId,
                toolName: "permissions_request",
                prompt: reason ?? permissionSummary(permissions),
                toolInput: nil
            )

        case "item/tool/requestUserInput":
            guard let threadId = params["threadId"] as? String else { return }
            let questions = parseQuestions(params["questions"] as? [[String: Any]] ?? [])
            guard let first = questions.first else { return }

            pendingRequestsByThread[threadId] = PendingRequest(
                requestId: id,
                threadId: threadId,
                kind: .userInput,
                requestedPermissions: nil,
                questionKeys: questions.map(\.key)
            )

            await postQuestionRequest(
                threadId: threadId,
                prompt: first.prompt,
                header: first.header,
                options: first.options,
                descriptions: first.descriptions
            )

        default:
            break
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard let websocket else {
            throw NSError(domain: "CodexAppServer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Websocket not connected",
            ])
        }

        requestSequence += 1
        let id = String(requestSequence)
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            Task {
                do {
                    try await websocket.send(.data(data))
                } catch {
                    if let continuation = pendingResponses.removeValue(forKey: id) {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func sendResponse(id: String, result: [String: Any]) async {
        guard let websocket else { return }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }

        do {
            try await websocket.send(.data(data))
        } catch {
            logger.error("Failed to send Codex response: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseThreadSnapshot(threadId: String, thread: [String: Any]) -> CodexAppThreadSnapshot? {
        let updatedAt = date(fromUnixTimestamp: thread["updatedAt"]) ?? Date()
        let turns = thread["turns"] as? [[String: Any]] ?? []

        var recentMessages: [(Int, ChatMessage)] = []
        var lastUserText: String?
        var lastAssistantText: String?
        var latestTurnId: String?
        var index = 0

        for (turnIndex, turn) in turns.enumerated() {
            if turnIndex == turns.count - 1 {
                latestTurnId = sanitizedText(turn["id"] as? String)
            }
            let items = turn["items"] as? [[String: Any]] ?? []
            for item in items {
                defer { index += 1 }
                switch item["type"] as? String {
                case "userMessage":
                    guard let text = parseUserMessageText(item["content"] as? [[String: Any]] ?? []) else { continue }
                    lastUserText = text
                    recentMessages.append((index, ChatMessage(isUser: true, text: text)))
                case "agentMessage":
                    guard let text = sanitizedText(item["text"] as? String) else { continue }
                    lastAssistantText = text
                    recentMessages.append((index, ChatMessage(isUser: false, text: text)))
                default:
                    continue
                }
            }
        }

        let status = agentStatus(from: thread["status"] as? [String: Any])

        return CodexAppThreadSnapshot(
            threadId: threadId,
            title: sanitizedText(thread["name"] as? String),
            cwd: sanitizedText(thread["cwd"] as? String),
            updatedAt: updatedAt,
            status: status,
            latestTurnId: latestTurnId,
            lastUserText: lastUserText,
            lastAssistantText: lastAssistantText,
            recentMessages: Array(recentMessages.sorted(by: { $0.0 < $1.0 }).suffix(3).map(\.1))
        )
    }

    private func agentStatus(from status: [String: Any]?) -> AgentStatus {
        guard let type = status?["type"] as? String else { return .idle }
        if type == "active" {
            let flags = status?["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") { return .waitingApproval }
            if flags.contains("waitingOnUserInput") { return .waitingQuestion }
            return .processing
        }
        return .idle
    }

    private func parseUserMessageText(_ content: [[String: Any]]) -> String? {
        let fragments = content.compactMap { item -> String? in
            switch item["type"] as? String {
            case "text":
                return sanitizedText(item["text"] as? String)
            case "mention", "skill":
                return sanitizedText(item["name"] as? String)
            case "image", "localImage":
                return "[Image]"
            default:
                return nil
            }
        }
        let joined = fragments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private func date(fromUnixTimestamp rawValue: Any?) -> Date? {
        if let value = rawValue as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        if let value = rawValue as? Double {
            return Date(timeIntervalSince1970: value)
        }
        if let value = rawValue as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        return nil
    }

    private func resolveCodexExecutable() -> String? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }

    private func permissionSummary(_ permissions: [String: Any]) -> String {
        let keys = permissions.keys.sorted()
        guard !keys.isEmpty else { return "Codex wants to broaden permissions for this turn." }
        return "Codex requests permissions: \(keys.joined(separator: ", "))"
    }

    private func parseQuestions(_ payloads: [[String: Any]]) -> [(key: String, prompt: String, header: String?, options: [String]?, descriptions: [String]?)] {
        payloads.compactMap { payload in
            let prompt = sanitizedText(payload["question"] as? String) ?? sanitizedText(payload["prompt"] as? String)
            guard let prompt else { return nil }
            let header = sanitizedText(payload["header"] as? String)
            let key = header ?? sanitizedText(payload["id"] as? String) ?? "answer"
            if let optionsPayload = payload["options"] as? [[String: Any]] {
                let options = optionsPayload.compactMap { sanitizedText($0["label"] as? String) }
                let descriptions = optionsPayload.compactMap { sanitizedText($0["description"] as? String) }
                return (
                    key: key,
                    prompt: prompt,
                    header: header,
                    options: options.isEmpty ? nil : options,
                    descriptions: descriptions.isEmpty ? nil : descriptions
                )
            }
            if let options = payload["options"] as? [String] {
                return (key: key, prompt: prompt, header: header, options: options, descriptions: nil)
            }
            return (key: key, prompt: prompt, header: header, options: nil, descriptions: nil)
        }
    }

    private func postPermissionRequest(threadId: String, toolName: String, prompt: String?, toolInput: [String: String]?) async {
        await MainActor.run {
            var userInfo: [String: Any] = [
                "threadId": threadId,
                "toolName": toolName,
            ]
            if let prompt {
                userInfo["prompt"] = prompt
            }
            if let toolInput {
                userInfo["toolInput"] = toolInput
            }
            NotificationCenter.default.post(name: .superIslandCodexPermissionRequested, object: nil, userInfo: userInfo)
        }
    }

    private func postQuestionRequest(
        threadId: String,
        prompt: String,
        header: String?,
        options: [String]?,
        descriptions: [String]?
    ) async {
        await MainActor.run {
            var userInfo: [String: Any] = [
                "threadId": threadId,
                "prompt": prompt,
            ]
            if let header {
                userInfo["header"] = header
            }
            if let options {
                userInfo["options"] = options
            }
            if let descriptions {
                userInfo["descriptions"] = descriptions
            }
            NotificationCenter.default.post(name: .superIslandCodexQuestionRequested, object: nil, userInfo: userInfo)
        }
    }

    private func postThreadRefreshRequested(threadId: String) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .superIslandCodexThreadRefreshRequested,
                object: nil,
                userInfo: ["threadId": threadId]
            )
        }
    }
}

extension Notification.Name {
    static let superIslandCodexPermissionRequested = Notification.Name("SuperIslandCodexPermissionRequested")
    static let superIslandCodexQuestionRequested = Notification.Name("SuperIslandCodexQuestionRequested")
    static let superIslandCodexThreadRefreshRequested = Notification.Name("SuperIslandCodexThreadRefreshRequested")
}
