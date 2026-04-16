import XCTest
@testable import SuperIsland

final class FirstLaunchExperienceTests: XCTestCase {
    func testConsumePendingPresentationReturnsTrueOnlyOnce() {
        let suiteName = "FirstLaunchExperienceTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Use an isolated defaults suite so the one-time marker behaves deterministically in tests.
        var experience = FirstLaunchExperience(defaults: defaults)

        XCTAssertTrue(experience.consumePendingPresentation())
        XCTAssertFalse(experience.consumePendingPresentation())
    }
}
