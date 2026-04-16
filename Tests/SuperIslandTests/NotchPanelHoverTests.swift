import XCTest
@testable import SuperIsland

final class NotchPanelHoverTests: XCTestCase {
    /// Collapsed mode should feel slightly magnetic instead of requiring an exact edge hit.
    func testCollapsedHoverHotZoneExtendsBeyondPanelBounds() {
        XCTAssertTrue(
            PanelPointerGeometry.containsPointer(
                panelFrame: CGRect(x: 100, y: 100, width: 360, height: 40),
                mouseLocation: CGPoint(x: 92, y: 96),
                isExpanded: false
            )
        )
    }

    /// The hot zone must still stay bounded so unrelated menu-bar movement does not expand the island.
    func testCollapsedHoverHotZoneStillRejectsFarAwayPointer() {
        XCTAssertFalse(
            PanelPointerGeometry.containsPointer(
                panelFrame: CGRect(x: 100, y: 100, width: 360, height: 40),
                mouseLocation: CGPoint(x: 70, y: 80),
                isExpanded: false
            )
        )
    }

    /// Expanded mode should stay close to the actual panel frame so hover-out collapse does not become sticky.
    func testExpandedHoverHotZoneUsesTighterInsets() {
        XCTAssertFalse(
            PanelPointerGeometry.containsPointer(
                panelFrame: CGRect(x: 100, y: 100, width: 360, height: 240),
                mouseLocation: CGPoint(x: 92, y: 94),
                isExpanded: true
            )
        )
    }

    /// Closed-state click-through is only enabled when global pointer tracking can
    /// still reopen the island from the background.
    func testClosedPresentationIgnoresMouseEventsOnlyWhenBackgroundTrackingIsAvailable() {
        XCTAssertTrue(
            PanelWindowController.shouldIgnoreMouseEvents(
                for: .closed,
                supportsBackgroundPointerTracking: true
            )
        )

        XCTAssertFalse(
            PanelWindowController.shouldIgnoreMouseEvents(
                for: .closed,
                supportsBackgroundPointerTracking: false
            )
        )
    }

    /// Opened and popping states must stay interactive so the panel controls remain clickable.
    func testOpenPresentationDoesNotIgnoreMouseEvents() {
        XCTAssertFalse(
            PanelWindowController.shouldIgnoreMouseEvents(
                for: .opened,
                supportsBackgroundPointerTracking: true
            )
        )

        XCTAssertFalse(
            PanelWindowController.shouldIgnoreMouseEvents(
                for: .popping,
                supportsBackgroundPointerTracking: true
            )
        )
    }

    /// Hover dismissal timing should stay long enough to tolerate small pointer slips.
    func testHoverDismissDelayMatchesLongerInteractionGracePeriod() {
        XCTAssertEqual(IslandPanelCoordinator.hoverDismissDelay(), 1.25, accuracy: 0.001)
    }

    func testCoordinatorMapsCompletionAndDetailToDeterministicInteractionStates() {
        XCTAssertTrue(
            IslandPanelCoordinator.interactionState(
                surface: .completionCard(sessionId: "done"),
                reason: .hover
            ) == .hovering
        )

        XCTAssertTrue(
            IslandPanelCoordinator.interactionState(
                surface: .sessionDetail(sessionId: "done"),
                reason: .pinned
            ) == .pinned
        )

        XCTAssertTrue(
            IslandPanelCoordinator.interactionState(
                surface: .sessionList,
                reason: .click
            ) == .expanded
        )
    }
}
