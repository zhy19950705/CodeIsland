import XCTest
@testable import SuperIsland
import SuperIslandCore

final class SessionListViewTests: XCTestCase {
    func testNeedsScrollWhenHeadersAndComposerPushContentPastThreshold() {
        XCTAssertTrue(
            SessionListView.needsScroll(
                totalSessionCount: 5,
                groupHeaderCount: 2,
                hasComposer: true,
                maxVisibleSessions: 5,
                onlySessionId: nil
            )
        )
    }

    func testNeedsScrollStaysFalseForSmallerGroupedLists() {
        XCTAssertFalse(
            SessionListView.needsScroll(
                totalSessionCount: 3,
                groupHeaderCount: 1,
                hasComposer: false,
                maxVisibleSessions: 5,
                onlySessionId: nil
            )
        )
    }

    func testNeedsScrollStaysFalseForCompletionOnlyView() {
        XCTAssertFalse(
            SessionListView.needsScroll(
                totalSessionCount: 10,
                groupHeaderCount: 3,
                hasComposer: true,
                maxVisibleSessions: 5,
                onlySessionId: "done"
            )
        )
    }

    func testUsesCompactRowKeepsRunningSessionsExpanded() {
        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .running,
                sessionId: "running",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )

        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .processing,
                sessionId: "processing",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )
    }

    func testUsesCompactRowStillCompactsIdleBackgroundSessions() {
        XCTAssertTrue(
            SessionListView.usesCompactRow(
                status: .idle,
                sessionId: "idle",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )
    }
}
