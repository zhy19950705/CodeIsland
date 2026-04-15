import Foundation
import os.log

private let codexRefreshLog = Logger(subsystem: "com.superisland", category: "CodexRefreshService")

@MainActor
final class CodexRefreshService {
    typealias ThreadReader = @Sendable (String) async throws -> CodexAppThreadSnapshot

    private let readThread: ThreadReader
    private var refreshTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var lastRefreshAt: Date = .distantPast
    private var latestTurnIds: [String: String] = [:]

    init(readThread: @escaping ThreadReader = { try await CodexAppServerClient.shared.readThread(threadId: $0) }) {
        self.readThread = readThread
    }

    func latestTurnId(for identifiers: [String]) -> String? {
        identifiers.compactMap { latestTurnIds[$0] }.first
    }

    func hasLatestTurnId(for identifiers: [String]) -> Bool {
        latestTurnId(for: identifiers) != nil
    }

    func storeLatestTurnId(_ turnId: String, for identifiers: [String]) {
        for identifier in identifiers where !identifier.isEmpty {
            latestTurnIds[identifier] = turnId
        }
    }

    func removeLatestTurnIds(for identifiers: [String]) {
        for identifier in identifiers where !identifier.isEmpty {
            latestTurnIds.removeValue(forKey: identifier)
        }
    }

    func clearLatestTurnIds() {
        latestTurnIds.removeAll()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func startLoop(interval: TimeInterval = 8, refresh: @escaping @MainActor () async -> Void) {
        stop()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await refresh()
            }
            _ = self
        }
    }

    func requestRefresh(minimumInterval: TimeInterval, refresh: @escaping @MainActor () async -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshAt) >= minimumInterval else { return }
        guard !refreshInFlight else { return }
        lastRefreshAt = now
        Task {
            await refresh()
        }
    }

    func performRefreshIfNeeded(
        isEnabled: Bool,
        trackedThreadIds: [String],
        limit: Int = 8,
        applySnapshot: @escaping @MainActor (CodexAppThreadSnapshot) -> Bool,
        didChange: @escaping @MainActor () -> Void
    ) async {
        guard isEnabled else { return }
        guard !trackedThreadIds.isEmpty else { return }
        guard !refreshInFlight else { return }

        refreshInFlight = true
        defer {
            refreshInFlight = false
            lastRefreshAt = Date()
        }

        var changed = false
        for threadId in trackedThreadIds.prefix(limit) {
            do {
                let snapshot = try await readThread(threadId)
                changed = applySnapshot(snapshot) || changed
            } catch {
                codexRefreshLog.debug("Codex app-server refresh failed for \(threadId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if changed {
            didChange()
        }
    }
}
