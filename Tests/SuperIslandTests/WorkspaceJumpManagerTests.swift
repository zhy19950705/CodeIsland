import XCTest
import AppKit
@testable import SuperIsland
import SuperIslandCore

@MainActor
final class WorkspaceJumpManagerTests: XCTestCase {
    // Editor presentation tests only need bundle lookup, so a tiny workspace stub keeps them deterministic.
    private final class WorkspaceStub: NSWorkspace {
        let applicationURLs: [String: URL]

        init(applicationURLs: [String: URL]) {
            self.applicationURLs = applicationURLs
            super.init()
        }

        override func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            applicationURLs[bundleIdentifier]
        }
    }

    // The lightweight render path only consults absolute executables, so a file-manager stub keeps those checks deterministic.
    private final class FileManagerStub: FileManager {
        let executablePaths: Set<String>

        init(executablePaths: Set<String>) {
            self.executablePaths = executablePaths
            super.init()
        }

        override func isExecutableFile(atPath path: String) -> Bool {
            executablePaths.contains(path)
        }
    }

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

    // Render-time editor actions only need a real directory; a temporary root keeps the resolve path environment-independent.
    private func makeWorkspaceDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
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

    func testEditorFallbackPrefersEditorTargetsBeforeFinderForTerminalHostedSessions() {
        var session = SessionSnapshot()
        session.source = "cmux"
        session.termBundleId = "com.cmuxterm.app"
        session.tmuxPane = "pane:1"

        let targets = WorkspaceJumpManager().editorFallbackChain(for: session).map(\.title)

        XCTAssertEqual(targets.first, "Cursor")
        XCTAssertEqual(targets.last, "Finder")
        XCTAssertFalse(targets.prefix(4).contains("cmux"))
        XCTAssertFalse(targets.prefix(4).contains("Terminal"))
    }

    func testEditorFallbackKeepsDetectedIDEHostAheadOfSourceSpecificApp() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.microsoft.VSCode"

        let targets = WorkspaceJumpManager().editorFallbackChain(for: session).map(\.title)

        XCTAssertEqual(targets.first, "VS Code")
        XCTAssertFalse(targets.prefix(2).contains("Terminal"))
    }

    func testPresentationEditorTargetFallsBackToFinderWhenWorkspaceExists() throws {
        let workspaceURL = try makeWorkspaceDirectory()
        let manager = WorkspaceJumpManager(
            fileManager: FileManagerStub(executablePaths: []),
            workspace: WorkspaceStub(applicationURLs: [:])
        )

        var session = SessionSnapshot()
        session.source = "codex"
        // Unsupported IDE hosts intentionally collapse the editor chain to Finder, which makes the
        // render-time path deterministic even on machines that have multiple editors installed.
        session.termBundleId = "com.apple.dt.Xcode"
        session.cwd = workspaceURL.path

        XCTAssertEqual(manager.resolvedPresentationEditorTarget(for: session), .finder)
    }

    func testPresentationEditorTargetPrefersInstalledEditorBundleBeforeFinder() throws {
        let workspaceURL = try makeWorkspaceDirectory()
        let manager = WorkspaceJumpManager(
            fileManager: FileManagerStub(executablePaths: []),
            workspace: WorkspaceStub(
                applicationURLs: [
                    "com.todesktop.230313mzl4w4u92": URL(fileURLWithPath: "/Applications/Cursor.app"),
                ]
            )
        )

        var session = SessionSnapshot()
        session.source = "cursor"
        session.cwd = workspaceURL.path

        XCTAssertEqual(manager.resolvedPresentationEditorTarget(for: session), .cursor)
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
