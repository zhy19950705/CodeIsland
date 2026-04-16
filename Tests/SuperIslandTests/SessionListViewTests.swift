import XCTest
@testable import SuperIsland
import SuperIslandCore

final class SessionListViewTests: XCTestCase {
    func testUsesCompactRowStaysFalseForCompletionOnlyView() {
        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .idle,
                needsCompletionReview: false,
                sessionId: "done",
                activeSessionId: nil,
                onlySessionId: "done"
            )
        )
    }

    func testUsesCompactRowKeepsRunningSessionsExpanded() {
        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .running,
                needsCompletionReview: false,
                sessionId: "running",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )

        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .processing,
                needsCompletionReview: false,
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
                needsCompletionReview: false,
                sessionId: "idle",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )
    }

    func testUsesCompactRowKeepsSelectedSessionExpanded() {
        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .idle,
                needsCompletionReview: false,
                sessionId: "selected",
                activeSessionId: "selected",
                onlySessionId: nil
            )
        )
    }

    func testUsesCompactRowKeepsPendingReviewSessionsExpanded() {
        XCTAssertFalse(
            SessionListView.usesCompactRow(
                status: .idle,
                needsCompletionReview: true,
                sessionId: "done",
                activeSessionId: nil,
                onlySessionId: nil
            )
        )
    }
}
