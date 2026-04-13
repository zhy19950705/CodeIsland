import XCTest
@testable import SuperIsland
import SuperIslandCore

@MainActor
final class AppStateSessionListPresentationTests: XCTestCase {
    func testSessionListPresentationInvalidatesCacheWhenSessionsChange() {
        let appState = AppState()

        var first = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        first.source = "claude"
        first.lastActivity = Date(timeIntervalSince1970: 100)
        appState.sessions["session-a"] = first

        let initial = appState.sessionListPresentation(groupingMode: "all")
        XCTAssertEqual(initial.totalSessionCount, 1)
        XCTAssertEqual(initial.groups.first?.ids, ["session-a"])

        var second = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        second.source = "codex"
        second.lastActivity = Date(timeIntervalSince1970: 200)
        appState.sessions["session-b"] = second

        let updated = appState.sessionListPresentation(groupingMode: "all")
        XCTAssertEqual(updated.totalSessionCount, 2)
        XCTAssertEqual(updated.groups.first?.ids, ["session-b", "session-a"])
    }

    func testSessionListPresentationReordersWhenActiveSessionChanges() {
        let appState = AppState()

        var waiting = SessionSnapshot(startTime: Date(timeIntervalSince1970: 10))
        waiting.source = "claude"
        waiting.status = .waitingApproval
        waiting.lastActivity = Date(timeIntervalSince1970: 100)

        var selected = SessionSnapshot(startTime: Date(timeIntervalSince1970: 20))
        selected.source = "codex"
        selected.status = .idle
        selected.lastActivity = Date(timeIntervalSince1970: 200)

        var running = SessionSnapshot(startTime: Date(timeIntervalSince1970: 30))
        running.source = "cursor"
        running.status = .running
        running.lastActivity = Date(timeIntervalSince1970: 300)

        appState.sessions = [
            "waiting": waiting,
            "selected": selected,
            "running": running,
        ]

        let baseline = appState.sessionListPresentation(groupingMode: "all")
        XCTAssertEqual(baseline.groups.first?.ids, ["waiting", "running", "selected"])

        appState.activeSessionId = "selected"

        let reordered = appState.sessionListPresentation(groupingMode: "all")
        XCTAssertEqual(reordered.groups.first?.ids, ["waiting", "selected", "running"])
    }
}
