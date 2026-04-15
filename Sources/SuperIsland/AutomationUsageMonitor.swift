import Foundation
import SuperIslandCore

struct UsageMonitorCommand {
    private let providers: [String]
    let explicitSocketPath: String?
    private let isDryRun: Bool
    let isVerbose: Bool

    init(arguments: [String]) {
        let rawProviders = Self.value(after: "--providers", in: arguments) ?? "claude,codex,cursor"
        self.providers = rawProviders
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        self.explicitSocketPath = Self.value(after: "--socket", in: arguments)
        self.isDryRun = arguments.contains("--dry-run")
        self.isVerbose = arguments.contains("--verbose")
    }

    func run() -> Int32 {
        let usageSnapshot = buildUsageSnapshot()
        let envelope = UsageUpdateEnvelope(usage: usageSnapshot)
        let encoder = JSONEncoder()

        guard let payload = try? encoder.encode(envelope) else {
            FileHandle.standardError.write(Data("Failed to encode usage snapshot.\n".utf8))
            return 1
        }

        guard isDryRun || UsageSnapshotStore.save(usageSnapshot) else {
            FileHandle.standardError.write(Data("Failed to persist usage snapshot.\n".utf8))
            return 1
        }

        if isDryRun {
            if let object = try? JSONSerialization.jsonObject(with: payload),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(pretty)
                if pretty.last != 0x0A {
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            }
            return 0
        }

        if let socketPath = sendToSocket(payload) {
            debug("sent usage_update to \(socketPath)")
        } else {
            debug("no active SuperIsland socket found, cache updated only")
        }

        return 0
    }

    private func buildUsageSnapshot() -> UsageSnapshot {
        var snapshots: [UsageProviderSnapshot] = []
        let now = Date().timeIntervalSince1970
        let previousSnapshot = UsageSnapshotStore.load()
        let previousClaudeSnapshot = previousSnapshot.providers.first(where: { $0.source == .claude })
        let previousCursorSnapshot = previousSnapshot.providers.first(where: { $0.source == .cursor })
        let claudeUsageHistory = ClaudeMonthlyUsageCalculator.loadUsageHistory()

        if providers.contains("claude"),
           let snapshot = buildClaudeSnapshot(
            now: now,
            previousSnapshot: previousClaudeSnapshot,
            history: claudeUsageHistory
           ) {
            snapshots.append(snapshot)
        }

        if providers.contains("codex"),
           let snapshot = buildCodexSnapshot(now: now) {
            snapshots.append(snapshot)
        }

        if providers.contains("cursor"),
           let snapshot = buildCursorSnapshot(now: now, previousSnapshot: previousCursorSnapshot) {
            snapshots.append(snapshot)
        }

        return UsageSnapshot(providers: snapshots.sorted { $0.source.sortOrder < $1.source.sortOrder })
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
