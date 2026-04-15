import XCTest
@testable import SuperIsland
import SuperIslandCore

@MainActor
final class AppStateSessionJumpMatchingTests: XCTestCase {
    func testMatchingSessionIdPrefersNewestWorkspaceMatch() {
        let appState = AppState()

        // Deeplinks should reopen the newest tracked session for a workspace so
        // notification jumps stay aligned with the visible session list order.
        var older = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        older.source = "claude"
        older.cwd = "/tmp/project"
        older.lastActivity = Date(timeIntervalSince1970: 100)

        var newer = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        newer.source = "claude"
        newer.cwd = "/tmp/project"
        newer.lastActivity = Date(timeIntervalSince1970: 200)

        appState.sessions = [
            "older": older,
            "newer": newer,
        ]

        XCTAssertEqual(
            appState.matchingSessionId(cwd: "/tmp/project", source: "claude"),
            "newer"
        )
    }

    func testMatchingSessionIdRespectsSourceFilterForSharedWorkspace() {
        let appState = AppState()

        // A shared repo can host multiple tools, so source filtering must keep
        // notification jumps on the exact terminal/editor the card represents.
        var claude = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        claude.source = "claude"
        claude.cwd = "/tmp/project"
        claude.lastActivity = Date(timeIntervalSince1970: 100)

        var codex = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        codex.source = "codex"
        codex.cwd = "/tmp/project"
        codex.lastActivity = Date(timeIntervalSince1970: 300)

        appState.sessions = [
            "claude": claude,
            "codex": codex,
        ]

        XCTAssertEqual(
            appState.matchingSessionId(cwd: "/tmp/project", source: "claude"),
            "claude"
        )
    }
}
