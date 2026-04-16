import XCTest
@testable import SuperIsland

final class SessionConversationDetailViewsTests: XCTestCase {
    // The detail timeline should only auto-scroll the first time a given session appears, not every time focus bounces.
    func testInitialScrollRunsOnlyOnceForSameSession() {
        XCTAssertTrue(
            DetailConversationTimeline.shouldPerformInitialScroll(
                sessionId: "session-a",
                lastInitialScrollSessionId: nil
            )
        )

        XCTAssertFalse(
            DetailConversationTimeline.shouldPerformInitialScroll(
                sessionId: "session-a",
                lastInitialScrollSessionId: "session-a"
            )
        )
    }

    // Changing to a different session should restore the initial bottom alignment for that newly opened detail surface.
    func testInitialScrollRunsAgainForDifferentSession() {
        XCTAssertTrue(
            DetailConversationTimeline.shouldPerformInitialScroll(
                sessionId: "session-b",
                lastInitialScrollSessionId: "session-a"
            )
        )
    }
}
