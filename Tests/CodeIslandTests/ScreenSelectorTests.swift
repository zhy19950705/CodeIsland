import XCTest
@testable import CodeIsland

final class ScreenSelectorTests: XCTestCase {
    func testScreenIdentifierMatchesExactDisplayID() {
        let identifier = ScreenIdentifier(displayID: 42, localizedName: "Studio Display")

        XCTAssertTrue(identifier.matches(displayID: 42, localizedName: "External Monitor"))
    }

    func testScreenIdentifierFallsBackToLocalizedName() {
        let identifier = ScreenIdentifier(displayID: 42, localizedName: "DELL U2720Q")

        XCTAssertTrue(identifier.matches(displayID: 108, localizedName: "DELL U2720Q"))
    }

    func testScreenIdentifierRejectsDifferentDisplayAndName() {
        let identifier = ScreenIdentifier(displayID: 42, localizedName: "Studio Display")

        XCTAssertFalse(identifier.matches(displayID: 108, localizedName: "Projector"))
    }
}
