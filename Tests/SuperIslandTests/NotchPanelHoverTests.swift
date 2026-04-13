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
}
