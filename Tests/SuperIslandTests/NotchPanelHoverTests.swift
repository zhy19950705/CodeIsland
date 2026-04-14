import XCTest
@testable import SuperIsland

final class NotchPanelHoverTests: XCTestCase {
    func testCollapsedNotchDeadZoneMatchesCenterCutout() {
        XCTAssertTrue(
            NotchPanelView.isInCollapsedNotchDeadZone(
                point: CGPoint(x: 180, y: 10),
                panelWidth: 360,
                notchWidth: 120,
                hasNotch: true,
                ignoresHover: true
            )
        )
    }

    func testCollapsedNotchDeadZoneIgnoresWingHover() {
        XCTAssertFalse(
            NotchPanelView.isInCollapsedNotchDeadZone(
                point: CGPoint(x: 64, y: 10),
                panelWidth: 360,
                notchWidth: 120,
                hasNotch: true,
                ignoresHover: true
            )
        )
    }

    func testCollapsedNotchDeadZoneDisabledWhenExpandedOrNotchedScreenMissing() {
        XCTAssertFalse(
            NotchPanelView.isInCollapsedNotchDeadZone(
                point: CGPoint(x: 180, y: 10),
                panelWidth: 360,
                notchWidth: 120,
                hasNotch: false,
                ignoresHover: true
            )
        )

        XCTAssertFalse(
            NotchPanelView.isInCollapsedNotchDeadZone(
                point: CGPoint(x: 180, y: 10),
                panelWidth: 360,
                notchWidth: 120,
                hasNotch: true,
                ignoresHover: false
            )
        )
    }

    func testExpandedHoverEndedIsIgnoredWhenMouseIsStillInsidePanelFrame() {
        XCTAssertTrue(
            NotchPanelView.shouldIgnoreExpandedHoverEnded(
                mouseLocation: CGPoint(x: 180, y: 24),
                panelFrame: CGRect(x: 100, y: 0, width: 220, height: 320),
                isExpanded: true
            )
        )
    }

    func testExpandedHoverEndedIsNotIgnoredWhenMouseLeftPanelOrPanelIsCollapsed() {
        XCTAssertFalse(
            NotchPanelView.shouldIgnoreExpandedHoverEnded(
                mouseLocation: CGPoint(x: 340, y: 24),
                panelFrame: CGRect(x: 100, y: 0, width: 220, height: 320),
                isExpanded: true
            )
        )

        XCTAssertFalse(
            NotchPanelView.shouldIgnoreExpandedHoverEnded(
                mouseLocation: CGPoint(x: 180, y: 24),
                panelFrame: CGRect(x: 100, y: 0, width: 220, height: 320),
                isExpanded: false
            )
        )
    }
}
