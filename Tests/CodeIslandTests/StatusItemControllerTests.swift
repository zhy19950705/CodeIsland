import XCTest
import CodeIslandCore
@testable import CodeIsland

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testPopoverContentDoesNotRebuildWhenAppStateInstanceIsUnchanged() {
        let appState = AppState()

        XCTAssertFalse(
            StatusItemController.needsPopoverContentRebuild(
                existingAppStateID: ObjectIdentifier(appState),
                newAppStateID: ObjectIdentifier(appState)
            )
        )
    }

    @MainActor
    func testPopoverContentRebuildsWhenAppStateInstanceChanges() {
        let first = AppState()
        let second = AppState()

        XCTAssertTrue(
            StatusItemController.needsPopoverContentRebuild(
                existingAppStateID: ObjectIdentifier(first),
                newAppStateID: ObjectIdentifier(second)
            )
        )
    }

    func testSummaryUsesActiveSessionProjectAndTitle() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/tmp/CodeIsland"
        session.sessionTitle = "Fix display mode"

        let summary = StatusItemController.summary(
            sessions: ["abc": session],
            activeSessionId: "abc",
            surface: .sessionList,
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "IDLE · CodeIsland · Fix display mode")
        XCTAssertEqual(summary?.sessionCount, 1)
        XCTAssertEqual(summary?.tone, .idle)
    }

    func testSummaryIncludesCountWhenMultipleSessionsExist() {
        var first = SessionSnapshot()
        first.source = "codex"
        first.cwd = "/tmp/CodeIsland"
        first.sessionTitle = "Fix display mode"

        var second = SessionSnapshot()
        second.source = "claude"
        second.cwd = "/tmp/VibeHub"
        second.sessionTitle = "Review hooks"

        let summary = StatusItemController.summary(
            sessions: ["a": first, "b": second],
            activeSessionId: "a",
            surface: .sessionList,
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "IDLE · CodeIsland · Fix display mode")
        XCTAssertEqual(summary?.sessionCount, 2)
    }

    func testSummaryPrefersWaitingStateAndToolLabel() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/tmp/CodeIsland"
        session.status = .waitingApproval
        session.currentTool = "Read"

        let summary = StatusItemController.summary(
            sessions: ["abc": session],
            activeSessionId: "abc",
            surface: .approvalCard(sessionId: "abc"),
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "WAIT · CodeIsland · Read")
        XCTAssertEqual(summary?.tone, .waiting)
    }

    func testSummaryUsesDonePrefixForCompletionCard() {
        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/tmp/VibeHub"
        session.sessionTitle = "Ship release"

        let summary = StatusItemController.summary(
            sessions: ["done": session],
            activeSessionId: "done",
            surface: .completionCard(sessionId: "done"),
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "DONE · VibeHub · Ship release")
        XCTAssertEqual(summary?.tone, .complete)
    }
}
