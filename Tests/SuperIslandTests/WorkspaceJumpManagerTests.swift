import XCTest
@testable import SuperIsland
import SuperIslandCore

@MainActor
final class WorkspaceJumpManagerTests: XCTestCase {
    // Keep a compact cmux topology fixture here so jump-resolution tests stay fast and deterministic.
    private func makeCmuxWorkspaces() -> [WorkspaceJumpManager.CmuxWorkspace] {
        [
            WorkspaceJumpManager.CmuxWorkspace(
                id: "workspace-id-1",
                ref: "workspace:1",
                panes: [
                    WorkspaceJumpManager.CmuxPane(
                        id: "pane-id-1",
                        ref: "pane:1",
                        surfaceRefs: ["surface:10", "surface:11"],
                        selectedSurfaceRef: "surface:10",
                        selectedSurfaceId: "surface-id-10",
                        surfaces: [
                            WorkspaceJumpManager.CmuxSurface(id: "surface-id-10", ref: "surface:10"),
                            WorkspaceJumpManager.CmuxSurface(id: "surface-id-11", ref: "surface:11"),
                        ]
                    ),
                    WorkspaceJumpManager.CmuxPane(
                        id: "pane-id-2",
                        ref: "pane:2",
                        surfaceRefs: ["surface:20"],
                        selectedSurfaceRef: "surface:20",
                        selectedSurfaceId: "surface-id-20",
                        surfaces: [
                            WorkspaceJumpManager.CmuxSurface(id: "surface-id-20", ref: "surface:20"),
                        ]
                    ),
                ]
            ),
        ]
    }

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

    func testCmuxSurfaceFocusTargetPrefersExactSurfaceWithinPane() {
        let manager = WorkspaceJumpManager()

        let target = manager.cmuxSurfaceFocusTarget(
            in: makeCmuxWorkspaces(),
            surfaceReference: "surface:11",
            surfaceIdentifier: nil
        )

        XCTAssertEqual(target?.workspaceReference, "workspace:1")
        XCTAssertEqual(target?.workspaceIdentifier, "workspace-id-1")
        XCTAssertEqual(target?.paneReference, "pane:1")
        XCTAssertEqual(target?.paneIdentifier, "pane-id-1")
        XCTAssertEqual(target?.surfaceReference, "surface:11")
        XCTAssertEqual(target?.surfaceIdentifier, "surface-id-11")
    }

    func testCmuxPaneFocusTargetFallsBackToSelectedSurface() {
        let manager = WorkspaceJumpManager()

        let target = manager.cmuxPaneFocusTarget(
            in: makeCmuxWorkspaces(),
            paneReference: "pane:1"
        )

        XCTAssertEqual(target?.workspaceReference, "workspace:1")
        XCTAssertEqual(target?.workspaceIdentifier, "workspace-id-1")
        XCTAssertEqual(target?.paneReference, "pane:1")
        XCTAssertEqual(target?.paneIdentifier, "pane-id-1")
        XCTAssertEqual(target?.surfaceReference, "surface:10")
        XCTAssertEqual(target?.surfaceIdentifier, "surface-id-10")
    }
}
