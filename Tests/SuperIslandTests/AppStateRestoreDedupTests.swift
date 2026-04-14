import XCTest
@testable import SuperIsland
import SuperIslandCore

@MainActor
final class AppStateRestoreDedupTests: XCTestCase {
    func testInsertRestoredSessionSkipsOlderHistoricalCodexDuplicateInSameCwd() {
        let appState = AppState()

        var latest = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        latest.source = "codex"
        latest.cwd = "/tmp/project"
        latest.lastActivity = Date(timeIntervalSince1970: 200)
        latest.isHistoricalSnapshot = true

        var older = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        older.source = "codex"
        older.cwd = "/tmp/project"
        older.lastActivity = Date(timeIntervalSince1970: 100)
        older.isHistoricalSnapshot = true

        XCTAssertTrue(appState.insertRestoredSession(sessionId: "latest", snapshot: latest))
        XCTAssertFalse(appState.insertRestoredSession(sessionId: "older", snapshot: older))
        XCTAssertEqual(Set(appState.sessions.keys), ["latest"])
    }

    func testInsertRestoredSessionAllowsDistinctLiveCodexSessionsInSameCwdWhenPIDsDiffer() {
        let appState = AppState()

        var first = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        first.source = "codex"
        first.cwd = "/tmp/project"
        first.lastActivity = Date(timeIntervalSince1970: 100)
        first.status = .processing
        first.cliPid = 101

        var second = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        second.source = "codex"
        second.cwd = "/tmp/project"
        second.lastActivity = Date(timeIntervalSince1970: 200)
        second.status = .processing
        second.cliPid = 202

        XCTAssertTrue(appState.insertRestoredSession(sessionId: "first", snapshot: first))
        XCTAssertTrue(appState.insertRestoredSession(sessionId: "second", snapshot: second))
        XCTAssertEqual(Set(appState.sessions.keys), ["first", "second"])
    }

    func testInsertRestoredSessionSkipsMatchingProviderThreadIdentity() {
        let appState = AppState()

        var tracked = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        tracked.source = "codex"
        tracked.cwd = "/tmp/project"
        tracked.lastActivity = Date(timeIntervalSince1970: 100)
        tracked.providerSessionId = "thread-123"

        var incoming = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        incoming.source = "codex"
        incoming.cwd = "/tmp/project"
        incoming.lastActivity = Date(timeIntervalSince1970: 200)
        incoming.providerSessionId = "thread-123"

        XCTAssertTrue(appState.insertRestoredSession(sessionId: "tracked-session", snapshot: tracked))
        XCTAssertFalse(appState.insertRestoredSession(sessionId: "thread-123", snapshot: incoming))
        XCTAssertEqual(Set(appState.sessions.keys), ["tracked-session"])
    }
}
