import XCTest
import SuperIslandCore
@testable import SuperIsland

// Resume support tests stay pure so command generation can be verified without launching terminals.
@MainActor
final class SessionResumeSupportTests: XCTestCase {
    func testCodexResumeCommandUsesThreadAndWorkspace() {
        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/tmp/demo project"
        session.providerSessionId = "thread-123"

        let command = SessionResumeSupport.resumeCommand(for: session, sessionId: "fallback")

        XCTAssertEqual(command, "cd '/tmp/demo project' && codex resume 'thread-123'")
    }

    func testClaudeResumeCommandUsesFlagSyntax() {
        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/tmp/claude workspace"

        let command = SessionResumeSupport.resumeCommand(for: session, sessionId: "session-456")

        XCTAssertEqual(command, "cd '/tmp/claude workspace' && claude --resume 'session-456'")
    }

    func testResumeCommandFallsBackToSessionIdWhenProviderIdIsMissing() {
        var session = SessionSnapshot()
        session.source = "codex"

        let command = SessionResumeSupport.resumeCommand(for: session, sessionId: "local-thread")

        XCTAssertEqual(command, "codex resume 'local-thread'")
    }

    func testMissingCodexThreadErrorMatchesDestroyedThreadMessages() {
        let error = NSError(
            domain: "CodexAppServer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Thread not found"]
        )

        XCTAssertTrue(SessionResumeSupport.isMissingCodexThreadError(error))
    }

    func testMissingCodexThreadErrorIgnoresTransportFailures() {
        let error = NSError(
            domain: "CodexAppServer",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Websocket not connected"]
        )

        XCTAssertFalse(SessionResumeSupport.isMissingCodexThreadError(error))
    }

    func testJumpToSessionAutoResumesOfflineClaudeSnapshot() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .idle
        appState.sessions["claude-session"] = session

        XCTAssertTrue(appState.shouldAutoResumeOnJumpForTesting(sessionId: "claude-session"))
    }

    func testJumpToSessionDoesNotAutoResumeActiveClaudeSession() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .processing
        appState.sessions["claude-session"] = session

        XCTAssertFalse(appState.shouldAutoResumeOnJumpForTesting(sessionId: "claude-session"))
    }

    func testTerminalHostedCodexJumpSkipsThreadValidation() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.googlecode.iterm2"
        appState.sessions["codex-cli-session"] = session

        XCTAssertFalse(appState.shouldValidateCodexJumpForTesting(sessionId: "codex-cli-session"))
    }

    func testNativeCodexJumpKeepsThreadValidation() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "codex"
        session.termBundleId = "com.openai.codex"
        appState.sessions["codex-app-session"] = session

        XCTAssertTrue(appState.shouldValidateCodexJumpForTesting(sessionId: "codex-app-session"))
    }
}
