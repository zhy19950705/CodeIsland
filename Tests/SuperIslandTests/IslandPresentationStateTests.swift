import XCTest
import SuperIslandCore
@testable import SuperIsland

final class IslandPresentationStateTests: XCTestCase {
    @MainActor
    func testOpenSessionListRestoresBlockingQuestionWhenStillPending() {
        let state = AppState()
        defer { state.teardown() }

        state.lastRestorableSurface = .questionCard(sessionId: "s-1")
        state.questionQueue = [
            QuestionRequest(
                event: HookEvent(
                    eventName: "Question",
                    sessionId: "s-1",
                    toolName: nil,
                    toolInput: nil,
                    rawJSON: [:]
                ),
                question: QuestionPayload(question: "Continue?", options: nil, descriptions: nil),
                answerAction: { _ in },
                skipAction: {}
            )
        ]

        state.openSessionList(reason: .click, animation: .linear(duration: 0))

        XCTAssertEqual(state.surface, .questionCard(sessionId: "s-1"))
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    @MainActor
    func testCompletionCardMapsToPoppingPresentationStatus() {
        let state = AppState()
        defer { state.teardown() }

        state.presentSurface(.completionCard(sessionId: "s-2"), reason: .notification)

        XCTAssertEqual(state.presentationState.status, .popping)
        XCTAssertEqual(state.presentationState.reason, .notification)
        XCTAssertEqual(state.presentationState.content, .completion(sessionId: "s-2"))
    }
}
