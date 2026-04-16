import XCTest
@testable import SuperIsland
import SuperIslandCore

final class IslandPanelCoordinatorTests: XCTestCase {
    @MainActor
    func testShowSessionListSurfaceReturnsToConcreteListInsteadOfRestoringDetail() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-1"] = SessionSnapshot()
        state.showSessionDetail("detail-1", reason: .pinned)

        state.panelCoordinator.showSessionListSurface()

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    @MainActor
    func testShowSessionListSurfaceKeepsClickOpenedListStableAfterDetailBackNavigation() async {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-guard"] = SessionSnapshot()
        state.showSessionDetail("detail-guard", reason: .pinned)

        // Returning from detail should keep the list stable even if the pointer moves
        // during the same click/animation sequence.
        state.panelCoordinator.showSessionListSurface()
        state.panelCoordinator.handleHover(
            inside: false,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.panelCoordinator.interactionState, .expanded)

        try? await Task.sleep(
            for: .seconds(IslandPanelCoordinator.navigationHoverGuardDelay() + 0.05)
        )

        // After the guard window expires, the list still stays open because it was
        // reopened via an explicit click-like navigation instead of a hover-open.
        state.panelCoordinator.handleHover(
            inside: false,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.panelCoordinator.interactionState, .expanded)
    }

    @MainActor
    func testHandleDetailBackTapCommitsListNavigationOnNextRunLoopTurn() async {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-back-1"] = SessionSnapshot()
        state.showSessionDetail("detail-back-1", reason: .pinned)

        state.panelCoordinator.handleDetailBackTap()

        // The staged navigation should not synchronously mutate the surface during the current click turn.
        XCTAssertEqual(state.surface, .sessionDetail(sessionId: "detail-back-1"))

        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    @MainActor
    func testPresentBlockingCardPromotesApprovalSurfaceWithoutChangingRestoreTargetLogic() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["detail-2"] = SessionSnapshot()
        state.showSessionDetail("detail-2", reason: .pinned)

        state.panelCoordinator.presentBlockingCard(.approvalCard(sessionId: "detail-2"))

        XCTAssertEqual(state.surface, .approvalCard(sessionId: "detail-2"))
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    @MainActor
    func testTogglePrimarySurfaceCollapsesExpandedPanelThroughCoordinator() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["list-1"] = SessionSnapshot()
        state.panelCoordinator.openSessionList(reason: .click)

        state.panelCoordinator.togglePrimarySurface()

        XCTAssertEqual(state.surface, .collapsed)
        XCTAssertEqual(state.lastOpenReason, .click)
    }

    @MainActor
    func testApplyBlockingPresentationCollapsesForNotificationWhenQueuesDrain() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["blocking-1"] = SessionSnapshot()
        state.panelCoordinator.presentBlockingCard(.approvalCard(sessionId: "blocking-1"), reason: .notification)

        state.panelCoordinator.applyBlockingPresentation(
            BlockingPresentationState(activeSessionId: nil, surface: .collapsed)
        )

        XCTAssertEqual(state.surface, .collapsed)
        XCTAssertEqual(state.lastOpenReason, .notification)
    }

    @MainActor
    func testPresentCompletionCardTracksNotificationSurface() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["done-1"] = SessionSnapshot()
        state.activeSessionId = "done-1"

        state.panelCoordinator.presentCompletionCard(sessionId: "done-1")

        XCTAssertEqual(state.surface, .completionCard(sessionId: "done-1"))
        XCTAssertEqual(state.lastOpenReason, .notification)
    }

    @MainActor
    func testFocusSessionActivatesSessionAndOpensListThroughCoordinator() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["focus-1"] = SessionSnapshot()

        XCTAssertTrue(state.panelCoordinator.focusSession(sessionId: "focus-1"))
        XCTAssertEqual(state.activeSessionId, "focus-1")
        XCTAssertTrue(state.surface.isExpanded)
    }

    @MainActor
    func testClickOpenedSessionListDoesNotAutoDismissOnPointerExit() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["click-list-1"] = SessionSnapshot()
        state.panelCoordinator.openSessionList(reason: .click)

        state.panelCoordinator.handleHover(
            inside: false,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.panelCoordinator.interactionState, .expanded)
    }

    @MainActor
    func testHoverOpenedSessionListRequiresRealExpandedEntryBeforeAutoDismiss() {
        let state = AppState()
        defer { state.teardown() }

        state.sessions["hover-list-1"] = SessionSnapshot()
        state.panelCoordinator.openSessionList(reason: .hover)

        state.panelCoordinator.handleHover(
            inside: false,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )

        XCTAssertEqual(state.surface, .sessionList)
        XCTAssertEqual(state.panelCoordinator.interactionState, .expanded)

        state.panelCoordinator.handleHover(
            inside: true,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )
        state.panelCoordinator.handleHover(
            inside: false,
            hoverActivationDelay: 0,
            collapseOnMouseLeave: true
        )

        XCTAssertEqual(state.panelCoordinator.interactionState, .dismissing)
    }
}
