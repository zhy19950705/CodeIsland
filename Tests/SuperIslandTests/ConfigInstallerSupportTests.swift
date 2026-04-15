import XCTest
@testable import SuperIsland

final class ConfigInstallerSupportTests: XCTestCase {
    // JSONC stripping must preserve strings because hook commands and URLs frequently contain comment-like tokens.
    func testStripJSONCommentsRemovesLineAndBlockCommentsButKeepsStrings() {
        let input = """
        {
          // line comment
          "url": "https://example.com//keep",
          /* block comment */
          "command": "echo /* literal */"
        }
        """

        let stripped = ConfigInstaller.stripJSONComments(input)

        XCTAssertFalse(stripped.contains("// line comment"))
        XCTAssertFalse(stripped.contains("/* block comment */"))
        XCTAssertTrue(stripped.contains(#""url": "https://example.com//keep""#))
        XCTAssertTrue(stripped.contains(#""command": "echo /* literal */""#))
    }

    func testVersionAtLeastHandlesMissingSegmentsAndOrdering() {
        XCTAssertTrue(ConfigInstaller.versionAtLeast("2.1.89", "2.1.89"))
        XCTAssertTrue(ConfigInstaller.versionAtLeast("2.1.90", "2.1.89"))
        XCTAssertTrue(ConfigInstaller.versionAtLeast("2.2", "2.1.99"))
        XCTAssertFalse(ConfigInstaller.versionAtLeast("2.1.88", "2.1.89"))
    }

    func testVersionAtLeastTreatsMissingPatchAsZero() {
        XCTAssertTrue(ConfigInstaller.versionAtLeast("2.1", "2.1.0"))
        XCTAssertFalse(ConfigInstaller.versionAtLeast("2.1", "2.1.1"))
    }
}
