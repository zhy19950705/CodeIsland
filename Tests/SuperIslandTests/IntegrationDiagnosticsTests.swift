import XCTest
@testable import SuperIsland

final class IntegrationDiagnosticsTests: XCTestCase {
    // OpenCode diagnostics should recognize both the current plugin file and the legacy vibe-island plugin path.
    func testOpenCodeConfigPathsIncludeCurrentAndLegacyPluginLocations() {
        XCTAssertEqual(
            CLIIntegrationID.opencode.configPaths,
            [
                "~/.config/opencode/plugins/superisland.js",
                "~/.config/opencode/plugins/vibe-island.js",
                "~/.config/opencode/config.json",
            ]
        )
    }

    func testCLIInstallMarkersRecognizeLegacyHookName() {
        XCTAssertEqual(CLIIntegrationID.opencode.installMarkers, ["superisland", "vibe-island"])
    }

    func testEditorBridgeHostsMapToMatchingExtensionHosts() {
        XCTAssertEqual(EditorBridgeHost.visualStudioCode.extensionHost, .visualStudioCode)
        XCTAssertEqual(EditorBridgeHost.cursor.extensionHost, .cursor)
        XCTAssertEqual(EditorBridgeHost.windsurf.extensionHost, .windsurf)
    }
}
