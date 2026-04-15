import XCTest
@testable import SuperIsland

final class SettingsTests: XCTestCase {
    func testDefaultDisplayModeIsMenuBar() {
        XCTAssertEqual(SettingsDefaults.displayMode, DisplayMode.menuBar.rawValue)
    }

    func testFallbackVersionMatchesLatestChangelogEntry() throws {
        let changelogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CHANGELOG.md")
        let changelog = try String(contentsOf: changelogURL, encoding: .utf8)
        let firstVersionLine = try XCTUnwrap(
            changelog
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("## [v") })
        )
        let latestVersion = firstVersionLine
            .replacingOccurrences(of: "## [v", with: "")
            .split(separator: "]")
            .first
            .map(String.init)

        XCTAssertEqual(AppVersion.fallback, latestVersion)
    }

    @MainActor
    func testDisplayModeFallbackReturnsMenuBarWhenStoredValueIsInvalid() {
        let suiteName = "SettingsTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("invalid-display-mode", forKey: SettingsKey.displayMode)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        XCTAssertEqual(settings.displayMode, .menuBar)
    }

    @MainActor
    func testDisplayModeMigrationMovesLegacyNotchDefaultToMenuBarOnNonNotchHardware() {
        let suiteName = "SettingsTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(DisplayMode.notch.rawValue, forKey: SettingsKey.displayMode)
        defaults.set("auto", forKey: SettingsKey.displayChoice)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults, hasPhysicalNotch: false)

        XCTAssertEqual(settings.displayMode, .menuBar)
        XCTAssertNotNil(defaults.object(forKey: SettingsKey.displayModeCompatibilityMigration))
    }

    @MainActor
    func testDisplayModeMigrationLeavesExplicitModeWhenNotchHardwareExists() {
        let suiteName = "SettingsTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(DisplayMode.notch.rawValue, forKey: SettingsKey.displayMode)
        defaults.set("auto", forKey: SettingsKey.displayChoice)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults, hasPhysicalNotch: true)

        XCTAssertEqual(settings.displayMode, .notch)
    }
}
