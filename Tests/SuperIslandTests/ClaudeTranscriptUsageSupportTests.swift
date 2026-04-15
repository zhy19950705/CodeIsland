import XCTest
import SuperIslandCore
@testable import SuperIsland

final class ClaudeTranscriptUsageSupportTests: XCTestCase {
    // Use a temp home directory so transcript and settings fixtures stay fully isolated from the real machine.
    func testResolveTranscriptPathPrefersClaudeProjectsDirectory() throws {
        let homeURL = makeTemporaryHomeDirectory()
        let cwd = "/Volumes/work/island/SuperIsland"
        let transcriptURL = homeURL
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent(cwd.claudeProjectDirEncoded(), isDirectory: true)
            .appendingPathComponent("session-123.jsonl", isDirectory: false)

        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: transcriptURL)

        let resolved = ClaudeTranscriptUsageSupport.resolveTranscriptPath(
            sessionId: "session-123",
            cwd: cwd,
            cachedPath: nil,
            homeDirectory: homeURL
        )

        XCTAssertEqual(resolved, transcriptURL.path)
    }

    // Read the newest assistant usage block and make sure context and output are computed from transcript usage fields.
    func testReadUsageSnapshotExtractsContextAndWindowSize() throws {
        let homeURL = makeTemporaryHomeDirectory()
        let settingsURL = homeURL.appendingPathComponent(".claude/settings.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"model":"claude-sonnet-4-6[1m]"}"#.utf8).write(to: settingsURL)

        let transcriptURL = homeURL.appendingPathComponent("sample.jsonl", isDirectory: false)
        let transcript = """
        {"message":{"role":"assistant","usage":{"input_tokens":1200,"cache_creation_input_tokens":300,"cache_read_input_tokens":200,"output_tokens":90}}}
        """
        try Data(transcript.utf8).write(to: transcriptURL)

        let snapshot = ClaudeTranscriptUsageSupport.readUsageSnapshot(
            transcriptPath: transcriptURL.path,
            homeDirectory: homeURL
        )

        XCTAssertEqual(snapshot?.contextTokens, 1700)
        XCTAssertEqual(snapshot?.outputTokens, 90)
        XCTAssertEqual(snapshot?.contextWindowSize, 1_000_000)
    }

    // The UI badge should prefer percentages so active Claude sessions are easy to scan in the notch.
    func testSessionSnapshotBuildsClaudeContextBadgeText() {
        var session = SessionSnapshot()
        session.source = "claude"
        session.contextTokens = 100_000
        session.contextWindowSize = 200_000
        session.outputTokens = 3_200

        XCTAssertEqual(session.claudeContextUsagePercent, 50)
        XCTAssertEqual(session.claudeContextBadgeText, "ctx 50%")
        XCTAssertEqual(session.claudeTokenDetailText, "ctx 50% · out 3.2K")
    }

    // Each test gets a unique temp home and cleans it up automatically.
    private func makeTemporaryHomeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
