import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class WorkspaceJumpManagerTests: XCTestCase {
    func testVSCodeHostBeatsCodexSource() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.microsoft.VSCode"

        let targets = WorkspaceJumpManager().fallbackTitles(for: session)

        XCTAssertEqual(targets.first, "VS Code")
        XCTAssertNotEqual(targets.first, "Codex")
    }

    func testVSCodeInsidersHostBeatsOpenCodeSource() {
        var session = SessionSnapshot()
        session.source = "opencode"
        session.termBundleId = "com.microsoft.VSCodeInsiders"

        let targets = WorkspaceJumpManager().fallbackTitles(for: session)

        XCTAssertEqual(targets.first, "VS Code Insiders")
        XCTAssertFalse(targets.prefix(2).contains("OpenCode"))
    }

    func testVSCodiumHostBeatsCodexSource() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.vscodium"

        let targets = WorkspaceJumpManager().fallbackTitles(for: session)

        XCTAssertEqual(targets.first, "VSCodium")
        XCTAssertFalse(targets.prefix(2).contains("Codex"))
    }

    func testTraeHostBeatsCodexSource() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.trae.app"

        let targets = WorkspaceJumpManager().fallbackTitles(for: session)

        XCTAssertEqual(targets.first, "Trae")
        XCTAssertFalse(targets.prefix(2).contains("Codex"))
    }

    func testUnsupportedIDEHostFallsBackToFinderInsteadOfNativeAppSource() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.apple.dt.Xcode"

        let targets = WorkspaceJumpManager().fallbackTitles(for: session)

        XCTAssertEqual(targets, ["Finder"])
    }
}
