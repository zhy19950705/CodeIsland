import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class AppStateCompletionReviewTests: XCTestCase {
    func testStopEventMarksSessionAsPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))
    }

    func testFocusSessionAcknowledgesPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))
        XCTAssertTrue(appState.focusSession(sessionId: "done"))
        XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
    }

    func testNewActivityClearsPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))

        appState.handleEvent(
            HookEvent(
                eventName: "UserPromptSubmit",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "prompt": "Continue with follow-up changes.",
                ]
            )
        )

        XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
    }
}
