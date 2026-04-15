import Foundation
import Network
import os.log
import SuperIslandCore

private let log = Logger(subsystem: "com.superisland", category: "HookServer")

@MainActor
class HookServer {
    private enum BlockingTimeout {
        static let seconds: TimeInterval = 300
    }

    private let appState: AppState
    nonisolated static var socketPath: String { SocketPath.path }
    private var listener: NWListener?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Clean up stale socket
        unlink(HookServer.socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: HookServer.socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            log.error("Failed to create NWListener: \(error.localizedDescription)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                log.info("HookServer listening on \(HookServer.socketPath)")
            case .failed(let error):
                log.error("HookServer failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(HookServer.socketPath)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveAll(connection: connection, accumulated: Data())
    }

    private static let maxPayloadSize = 1_048_576  // 1MB safety limit

    /// Recursively receive all data until EOF, then process
    private func receiveAll(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }

                // On error with no data, just drop the connection
                if error != nil && accumulated.isEmpty && content == nil {
                    connection.cancel()
                    return
                }

                var data = accumulated
                if let content { data.append(content) }

                // Safety: reject oversized payloads
                if data.count > Self.maxPayloadSize {
                    log.warning("Payload too large (\(data.count) bytes), dropping connection")
                    connection.cancel()
                    return
                }

                if isComplete || error != nil {
                    self.processRequest(data: data, connection: connection)
                } else {
                    self.receiveAll(connection: connection, accumulated: data)
                }
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        if let usageEnvelope = try? JSONDecoder().decode(UsageUpdateEnvelope.self, from: data),
           usageEnvelope.type == "usage_update" {
            _ = UsageSnapshotStore.save(usageEnvelope.usage)
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        guard let event = HookEvent(from: data) else {
            sendResponse(connection: connection, data: Data("{\"error\":\"parse_failed\"}".utf8))
            return
        }

        if let rawSource = event.rawJSON["_source"] as? String,
           SessionSnapshot.normalizedSupportedSource(rawSource) == nil {
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        if event.eventName == "PermissionRequest" {
            let sessionId = event.sessionId ?? "default"

            // Auto-approve safe internal tools without showing UI
            if HookPolicy.shared.shouldAutoApprove(toolName: event.toolName) {
                sendResponse(connection: connection, data: HookResponsePayload.permissionAllow())
                return
            }

            // AskUserQuestion is a question, not a permission — route to QuestionBar
            if event.toolName == "AskUserQuestion" {
                monitorPeerDisconnect(connection: connection, sessionId: sessionId)
                Task {
                    let responseBody = await withCheckedContinuation { continuation in
                        let requestId = appState.handleAskUserQuestion(event, continuation: continuation)
                        self.scheduleQuestionTimeout(requestId: requestId, sessionId: sessionId, isFromPermission: true)
                    }
                    self.sendResponse(connection: connection, data: responseBody)
                }
                return
            }
            monitorPeerDisconnect(connection: connection, sessionId: sessionId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    let requestId = appState.handlePermissionRequest(event, continuation: continuation)
                    self.schedulePermissionTimeout(requestId: requestId, sessionId: sessionId)
                }
                self.sendResponse(connection: connection, data: responseBody)
            }
        } else if EventNormalizer.normalize(event.eventName) == "Notification",
                  QuestionPayload.from(event: event) != nil {
            let questionSessionId = event.sessionId ?? "default"
            monitorPeerDisconnect(connection: connection, sessionId: questionSessionId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    if let requestId = appState.handleQuestion(event, continuation: continuation) {
                        self.scheduleQuestionTimeout(requestId: requestId, sessionId: questionSessionId, isFromPermission: false)
                    }
                }
                self.sendResponse(connection: connection, data: responseBody)
            }
        } else {
            appState.handleEvent(event)
            sendResponse(connection: connection, data: Data("{}".utf8))
        }
    }

    /// Per-connection state used by the disconnect monitor.
    /// `responded` flips to true once we've sent the response, so our own
    /// `connection.cancel()` inside `sendResponse` does not masquerade as a
    /// peer disconnect.
    private final class ConnectionContext {
        var responded: Bool = false
    }

    private var connectionContexts: [ObjectIdentifier: ConnectionContext] = [:]

    /// Watch for bridge process disconnect — indicates the bridge process actually died
    /// (e.g. user Ctrl-C'd Claude Code), NOT a normal half-close.
    ///
    /// Previously this used `connection.receive(min:1, max:1)` which triggered on EOF.
    /// But the bridge always does `shutdown(SHUT_WR)` after sending the request (see
    /// SuperIslandBridge/main.swift), which produces an immediate EOF on the read side.
    /// That caused every PermissionRequest to be auto-drained as `deny` before the UI
    /// card was even visible. We now rely on `stateUpdateHandler` transitioning to
    /// `cancelled`/`failed` — which only happens on real socket teardown, not half-close.
    private func monitorPeerDisconnect(connection: NWConnection, sessionId: String) {
        let key = ObjectIdentifier(connection)
        if connectionContexts[key] != nil {
            return
        }
        let context = ConnectionContext()
        connectionContexts[key] = context

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .cancelled, .failed:
                    if !context.responded {
                        self.appState.handlePeerDisconnect(sessionId: sessionId)
                    }
                    self.connectionContexts.removeValue(forKey: key)
                default:
                    break
                }
            }
        }
    }

    private func sendResponse(connection: NWConnection, data: Data) {
        // Mark as responded BEFORE cancel() so the disconnect monitor ignores our own teardown.
        if let context = connectionContexts[ObjectIdentifier(connection)] {
            context.responded = true
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func schedulePermissionTimeout(requestId: UUID, sessionId: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BlockingTimeout.seconds))
            guard let self else { return }
            guard self.appState.timeoutPermissionRequest(id: requestId) else { return }
            log.warning("PermissionRequest timed out for session \(sessionId, privacy: .public)")
        }
    }

    private func scheduleQuestionTimeout(requestId: UUID, sessionId: String, isFromPermission: Bool) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BlockingTimeout.seconds))
            guard let self else { return }
            guard self.appState.timeoutQuestionRequest(id: requestId) else { return }
            let kind = isFromPermission ? "AskUserQuestion" : "Question"
            log.warning("\(kind, privacy: .public) timed out for session \(sessionId, privacy: .public)")
        }
    }
}
