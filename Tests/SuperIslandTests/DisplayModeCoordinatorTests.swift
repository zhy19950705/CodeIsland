import XCTest
@testable import SuperIsland

final class DisplayModeCoordinatorTests: XCTestCase {
    func testAutoResolvesToNotchWhenSelectedScreenHasPhysicalNotch() {
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.auto, hasPhysicalNotch: true, screenCount: 2),
            .notch
        )
    }

    func testAutoResolvesToMenuBarWhenSelectedScreenHasNoPhysicalNotch() {
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.auto, hasPhysicalNotch: false, screenCount: 2),
            .menuBar
        )
    }

    func testAutoResolvesToMenuBarForSingleScreenWithoutPhysicalNotch() {
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.auto, hasPhysicalNotch: false, screenCount: 1),
            .menuBar
        )
    }

    func testExplicitModesRemainUnchanged() {
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.notch, hasPhysicalNotch: false, screenCount: 1),
            .notch
        )
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.menuBar, hasPhysicalNotch: true, screenCount: 3),
            .menuBar
        )
    }

    func testExplicitMenuBarRemainsMenuBarForSingleScreenSetup() {
        XCTAssertEqual(
            DisplayModeCoordinator.resolveMode(.menuBar, hasPhysicalNotch: false, screenCount: 1),
            .menuBar
        )
    }
}
