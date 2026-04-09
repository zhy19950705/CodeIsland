import XCTest
@testable import CodeIsland

final class MascotOverridesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MascotOverridesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEffectiveSourceFallsBackToClientSource() {
        XCTAssertEqual(MascotOverrides.effectiveSource(for: "claude", defaults: defaults), "claude")
        XCTAssertNil(MascotOverrides.override(for: "claude", defaults: defaults))
    }

    func testSetOverrideStoresCustomMascotAndBumpsVersion() {
        MascotOverrides.setOverride("codex", for: "claude", defaults: defaults)

        XCTAssertEqual(MascotOverrides.override(for: "claude", defaults: defaults), "codex")
        XCTAssertEqual(MascotOverrides.effectiveSource(for: "claude", defaults: defaults), "codex")
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.mascotOverridesVersion), 1)
    }

    func testSetOverrideClearsWhenMatchingClientSource() {
        MascotOverrides.setOverride("codex", for: "claude", defaults: defaults)
        MascotOverrides.setOverride("claude", for: "claude", defaults: defaults)

        XCTAssertNil(MascotOverrides.override(for: "claude", defaults: defaults))
        XCTAssertEqual(MascotOverrides.effectiveSource(for: "claude", defaults: defaults), "claude")
    }

    func testResetAllClearsEveryStoredOverride() {
        MascotOverrides.setOverride("codex", for: "claude", defaults: defaults)
        MascotOverrides.setOverride("gemini", for: "cursor", defaults: defaults)

        XCTAssertEqual(MascotOverrides.customizedCount(defaults: defaults), 2)

        MascotOverrides.resetAll(defaults: defaults)

        XCTAssertEqual(MascotOverrides.customizedCount(defaults: defaults), 0)
        XCTAssertNil(MascotOverrides.override(for: "claude", defaults: defaults))
        XCTAssertNil(MascotOverrides.override(for: "cursor", defaults: defaults))
    }
}
