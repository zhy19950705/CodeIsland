import XCTest
@testable import SuperIsland

@MainActor
final class HookPolicyTests: XCTestCase {
    func testDefaultPolicyAutoApprovesKnownInternalTool() {
        let policy = HookPolicy()

        XCTAssertTrue(policy.shouldAutoApprove(toolName: "TaskCreate"))
        XCTAssertFalse(policy.shouldAutoApprove(toolName: "Write"))
    }

    func testCustomPolicyUsesDefaultsOverride() {
        let suiteName = "HookPolicyTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["Write", "Edit"], forKey: SettingsKey.hookAutoApproveTools)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let policy = HookPolicy(defaults: defaults)

        XCTAssertTrue(policy.shouldAutoApprove(toolName: "Write"))
        XCTAssertTrue(policy.shouldAutoApprove(toolName: "Edit"))
        XCTAssertFalse(policy.shouldAutoApprove(toolName: "TaskCreate"))
    }
}
