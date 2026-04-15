import Foundation
import SuperIslandCore

// A small polling monitor is enough here because Claude already writes token usage into local transcripts.
@MainActor
final class ClaudeRealtimeTokenMonitor {
    private struct MonitorTarget {
        let sessionId: String
        let cwd: String?
        let cachedTranscriptPath: String?
    }

    private struct MonitorResult {
        let sessionId: String
        let snapshot: ClaudeTranscriptUsageSnapshot?
        let resolvedTranscriptPath: String?
    }

    private weak var appState: AppState?
    private let refreshIntervalNanoseconds: UInt64
    private var refreshTask: Task<Void, Never>?

    init(appState: AppState, refreshIntervalSeconds: TimeInterval = 10) {
        self.appState = appState
        self.refreshIntervalNanoseconds = UInt64(max(refreshIntervalSeconds, 1) * 1_000_000_000)
    }

    // Start one polling task for the whole app and refresh immediately so the UI fills without waiting 10s.
    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOnce()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.refreshIntervalNanoseconds)
                await self.refreshOnce()
            }
        }
    }

    // Cancel the loop when the app stops session discovery or tears down in tests.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // Refresh only Claude sessions because other providers use different transcript formats.
    func refreshOnce() async {
        guard let appState else { return }

        let targets = appState.sessions.compactMap { sessionId, session -> MonitorTarget? in
            guard session.source == "claude" else { return nil }
            return MonitorTarget(
                sessionId: sessionId,
                cwd: session.cwd,
                cachedTranscriptPath: session.claudeTranscriptPath
            )
        }

        guard !targets.isEmpty else { return }

        let results = await Task.detached(priority: .utility) {
            targets.map { target in
                let transcriptPath = ClaudeTranscriptUsageSupport.resolveTranscriptPath(
                    sessionId: target.sessionId,
                    cwd: target.cwd,
                    cachedPath: target.cachedTranscriptPath
                )
                let snapshot = transcriptPath.flatMap {
                    ClaudeTranscriptUsageSupport.readUsageSnapshot(transcriptPath: $0)
                }
                return MonitorResult(
                    sessionId: target.sessionId,
                    snapshot: snapshot,
                    resolvedTranscriptPath: transcriptPath
                )
            }
        }.value

        for result in results {
            guard appState.sessions[result.sessionId]?.source == "claude" else { continue }

            appState.sessions[result.sessionId]?.claudeTranscriptPath = result.resolvedTranscriptPath
            appState.sessions[result.sessionId]?.contextTokens = result.snapshot?.contextTokens
            appState.sessions[result.sessionId]?.outputTokens = result.snapshot?.outputTokens
            appState.sessions[result.sessionId]?.contextWindowSize = result.snapshot?.contextWindowSize
        }
    }
}
