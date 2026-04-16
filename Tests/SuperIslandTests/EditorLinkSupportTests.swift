import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class EditorLinkSupportTests: XCTestCase {
    // Relative transcript links should resolve against the session cwd so repo-local file references open correctly.
    func testResolvedLocalTargetExpandsRelativePathAgainstWorkingDirectory() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            from: URL(string: "scripts/islandctl.sh#L27")!,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertEqual(target?.filePath, "/Volumes/work/island/SuperIsland/scripts/islandctl.sh")
        XCTAssertEqual(target?.line, 27)
    }

    // Absolute file URLs should keep their own path and preserve line fragments for `--goto` editor launches.
    func testResolvedLocalTargetKeepsAbsoluteFileURLAndLineFragment() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            from: URL(string: "file:///tmp/App.swift#L18-L24")!,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertEqual(target?.filePath, "/tmp/App.swift")
        XCTAssertEqual(target?.line, 18)
    }

    // Web links should bypass the editor path entirely so transcript citations still open in the browser.
    func testResolvedLocalTargetIgnoresWebLinks() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            from: URL(string: "https://example.com/docs")!,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertNil(target)
    }

    // Tool-result buttons can provide a path string directly without wrapping it in markdown URL syntax first.
    func testResolvedLocalTargetNormalizesDirectPathInput() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            path: "./popup/updates.js",
            line: 9,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertEqual(target?.filePath, "/Volumes/work/island/SuperIsland/popup/updates.js")
        XCTAssertEqual(target?.line, 9)
    }

    // Transcript links often encode line numbers as `path:line`, so parsing should preserve the real file path.
    func testResolvedLocalTargetParsesColonLineSuffix() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            from: URL(string: "Sources/SuperIsland/EditorLinkSupport.swift:1")!,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertEqual(target?.filePath, "/Volumes/work/island/SuperIsland/Sources/SuperIsland/EditorLinkSupport.swift")
        XCTAssertEqual(target?.line, 1)
    }

    // Some editor-generated links include both line and column, but editor jumps still only need the line component.
    func testResolvedLocalTargetParsesColonLineAndColumnSuffix() {
        let target = EditorLinkSupport.resolvedLocalTarget(
            from: URL(string: "Sources/SuperIsland/EditorLinkSupport.swift:12:3")!,
            workingDirectory: "/Volumes/work/island/SuperIsland"
        )

        XCTAssertEqual(target?.filePath, "/Volumes/work/island/SuperIsland/Sources/SuperIsland/EditorLinkSupport.swift")
        XCTAssertEqual(target?.line, 12)
    }

    // File links should prefer the `code` family before source-specific editors so clicking a path behaves like `code file.swift`.
    func testPreferredTargetsFavorVSCodeBeforeCursorForCursorSession() {
        var session = SessionSnapshot()
        session.source = "cursor"
        session.termBundleId = "com.todesktop.230313mzl4w4u92"

        let targets = EditorLinkSupport.preferredTargets(
            manager: WorkspaceJumpManager(),
            session: session
        ).map(\.title)

        XCTAssertEqual(targets.first, "VS Code")
        XCTAssertTrue(targets.prefix(4).contains("Cursor"))
    }

    // VS Code host sessions should still keep VS Code first after the file-link specific reordering.
    func testPreferredTargetsKeepVSCodeHostFirst() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.microsoft.VSCode"

        let targets = EditorLinkSupport.preferredTargets(
            manager: WorkspaceJumpManager(),
            session: session
        ).map(\.title)

        XCTAssertEqual(targets.first, "VS Code")
    }
}
