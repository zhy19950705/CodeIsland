import Foundation

enum WorkspacePaths {
    // Keep synthetic agent worktree filters centralized so discovery and hook ingestion stay aligned.
    static let syntheticAgentWorktreeMarkers = [
        "/.claude/worktrees/agent-",
        "/.git/worktrees/agent-",
    ]

    static func isSyntheticAgentWorktree(_ cwd: String) -> Bool {
        syntheticAgentWorktreeMarkers.contains { cwd.contains($0) }
    }
}

enum AppRuntimeConstants {
    // Preview sessions use a stable prefix so debug fixtures and tests can be cleaned up consistently.
    static let testingSessionPrefix = "preview-"

    // Debounce hook bursts without delaying the first derived-state refresh.
    static let derivedStateRefreshInterval: TimeInterval = 0.05
}
