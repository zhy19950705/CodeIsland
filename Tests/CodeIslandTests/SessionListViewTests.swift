import XCTest
@testable import CodeIsland

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
}
