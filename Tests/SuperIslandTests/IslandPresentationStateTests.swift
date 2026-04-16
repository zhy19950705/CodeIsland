import XCTest
import SuperIslandCore
@testable import SuperIsland

final class IslandPresentationStateTests: XCTestCase {
    // Blocking reopen should still prefer the pending question over any stale restorable surface.
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

    // Dedicated detail surfaces should be restorable so closing and reopening behaves like MioIsland chat mode.
    @MainActor
    func testShowSessionDetailMarksDetailAsRestorableSurface() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-1"] = SessionSnapshot()

        state.showSessionDetail("detail-1")

        XCTAssertEqual(state.activeSessionId, "detail-1")
        XCTAssertEqual(state.surface, .sessionDetail(sessionId: "detail-1"))
        XCTAssertEqual(state.lastRestorableSurface, .sessionDetail(sessionId: "detail-1"))
        XCTAssertEqual(state.presentationState.content, .detail(sessionId: "detail-1"))
    }

    // Hover reopen should stay on the session list so the panel does not jump back into detail unexpectedly.
    @MainActor
    func testOpenSessionListHoverReturnsToSessionListInsteadOfDetailSurface() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-2"] = SessionSnapshot()
        state.lastRestorableSurface = .sessionDetail(sessionId: "detail-2")

        state.openSessionList(reason: .hover, animation: .linear(duration: 0))

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.lastOpenReason, .hover)
    }

    // Explicit reopen actions should still restore the active detail surface while the session exists.
    @MainActor
    func testOpenSessionListClickRestoresSessionDetailSurface() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-3"] = SessionSnapshot()
        state.lastRestorableSurface = .sessionDetail(sessionId: "detail-3")

        state.openSessionList(reason: .click, animation: .linear(duration: 0))

        XCTAssertEqual(state.surface, .sessionDetail(sessionId: "detail-3"))
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    // Pinned detail opens should carry an explicit reason so hover-out logic can ignore transient dismissals.
    @MainActor
    func testShowSessionDetailPinnedReasonPersistsInPresentationState() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-4"] = SessionSnapshot()

        state.showSessionDetail("detail-4", reason: .pinned)

        XCTAssertEqual(state.surface, .sessionDetail(sessionId: "detail-4"))
        XCTAssertEqual(state.lastOpenReason, .pinned)
        XCTAssertEqual(state.presentationState.content, .detail(sessionId: "detail-4"))
    }

    func testSurfaceMotionProfileSeparatesListDetailAndTransientCards() {
        XCTAssertEqual(IslandSurface.sessionList.motionProfile, .list)
        XCTAssertEqual(IslandSurface.sessionDetail(sessionId: "detail-5").motionProfile, .detail)
        XCTAssertEqual(IslandSurface.approvalCard(sessionId: "detail-5").motionProfile, .blockingCard)
        XCTAssertEqual(IslandSurface.completionCard(sessionId: "detail-5").motionProfile, .completion)
        XCTAssertEqual(IslandSurface.collapsed.motionProfile, .collapsed)
    }

    func testSurfaceTransitionIdentityKeepsConcreteSurfaceInstancesDistinct() {
        XCTAssertEqual(IslandSurface.sessionList.transitionIdentity, "surface-session-list")
        XCTAssertEqual(
            IslandSurface.sessionDetail(sessionId: "detail-6").transitionIdentity,
            "surface-session-detail-detail-6"
        )
        XCTAssertEqual(
            IslandSurface.questionCard(sessionId: "detail-6").transitionIdentity,
            "surface-question-detail-6"
        )
        XCTAssertNotEqual(
            IslandSurface.questionCard(sessionId: "detail-6").transitionIdentity,
            IslandSurface.questionCard(sessionId: "detail-7").transitionIdentity
        )
    }
}
