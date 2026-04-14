import XCTest
@testable import SuperIsland

final class SettingsTests: XCTestCase {
    func testDefaultDisplayModeIsMenuBar() {
        XCTAssertEqual(SettingsDefaults.displayMode, DisplayMode.menuBar.rawValue)
    }

    @MainActor
    func testDisplayModeFallbackReturnsMenuBarWhenStoredValueIsInvalid() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: SettingsKey.displayMode)

        defaults.set("invalid-display-mode", forKey: SettingsKey.displayMode)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: SettingsKey.displayMode)
            } else {
                defaults.removeObject(forKey: SettingsKey.displayMode)
            }
        }

        XCTAssertEqual(SettingsManager.shared.displayMode, .menuBar)
    }
}
