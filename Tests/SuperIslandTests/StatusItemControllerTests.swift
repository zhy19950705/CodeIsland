import XCTest
import SuperIslandCore
@testable import SuperIsland

final class StatusItemControllerTests: XCTestCase {
    func testResolvedPresentationUsesPopoverForMenuBarMode() {
        XCTAssertEqual(
            StatusItemController.resolvedPresentation(resolvedDisplayMode: .menuBar),
            .popover
        )
    }

    func testResolvedPresentationUsesListPopoverForNotchMode() {
        XCTAssertEqual(
            StatusItemController.resolvedPresentation(resolvedDisplayMode: .notch),
            .listPopover
        )
    }

    func testResolvedPresentationUsesListPopoverForAutoResolvedNotchStyleModes() {
        XCTAssertEqual(
            StatusItemController.resolvedPresentation(resolvedDisplayMode: .auto),
            .listPopover
        )
    }

    @MainActor
    func testPopoverContentDoesNotRebuildWhenAppStateInstanceIsUnchanged() {
        let appState = AppState()

        XCTAssertFalse(
            StatusItemController.needsPopoverContentRebuild(
                existingAppStateID: ObjectIdentifier(appState),
                newAppStateID: ObjectIdentifier(appState),
                existingMode: .contextual,
                newMode: .contextual
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
                newAppStateID: ObjectIdentifier(second),
                existingMode: .contextual,
                newMode: .contextual
            )
        )
    }

    @MainActor
    func testPopoverContentRebuildsWhenPopoverModeChanges() {
        let appState = AppState()

        XCTAssertTrue(
            StatusItemController.needsPopoverContentRebuild(
                existingAppStateID: ObjectIdentifier(appState),
                newAppStateID: ObjectIdentifier(appState),
                existingMode: .contextual,
                newMode: .sessionListOnly
            )
        )
    }

    func testSummaryUsesActiveSessionProjectAndTitle() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/tmp/SuperIsland"
        session.sessionTitle = "Fix display mode"

        let summary = StatusItemController.summary(
            sessions: ["abc": session],
            activeSessionId: "abc",
            surface: .sessionList,
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "IDLE · SuperIsland · Fix display mode")
        XCTAssertEqual(summary?.sessionCount, 1)
        XCTAssertEqual(summary?.tone, .idle)
    }

    func testSummaryIncludesCountWhenMultipleSessionsExist() {
        var first = SessionSnapshot()
        first.source = "codex"
        first.cwd = "/tmp/SuperIsland"
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

        XCTAssertEqual(summary?.text, "IDLE · SuperIsland · Fix display mode")
        XCTAssertEqual(summary?.sessionCount, 2)
    }

    func testSummaryPrefersWaitingStateAndToolLabel() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/tmp/SuperIsland"
        session.status = .waitingApproval
        session.currentTool = "Read"

        let summary = StatusItemController.summary(
            sessions: ["abc": session],
            activeSessionId: "abc",
            surface: .approvalCard(sessionId: "abc"),
            showDetail: true
        )

        XCTAssertEqual(summary?.text, "WAIT · SuperIsland · Read")
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
