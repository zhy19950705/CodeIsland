import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AppStatePermissionTests: XCTestCase {
    func testApprovePermissionUpdatesCodexSessionWithoutExclusivityConflict() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "codex"
        session.status = .waitingApproval
        appState.sessions["codex-session"] = session

        let event = HookEvent(
            eventName: "PermissionRequest",
            sessionId: "codex-session",
            toolName: "Edit",
            toolInput: ["file_path": "/tmp/test.swift"]
        )

        var approveCalls: [Bool] = []
        appState.permissionQueue = [
            PermissionRequest(
                event: event,
                approveAction: { always in
                    approveCalls.append(always)
                },
                denyAction: {}
            )
        ]

        appState.approvePermission(always: false)

        XCTAssertEqual(approveCalls, [false])
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        if case .processing = appState.sessions["codex-session"]?.status {
        } else {
            XCTFail("Expected codex session to move into processing after approval")
        }
    }

    func testDenyPermissionUpdatesNonCodexSessionWithoutExclusivityConflict() {
        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .waitingApproval
        session.currentTool = "Write"
        session.toolDescription = "test file"
        appState.sessions["claude-session"] = session

        let event = HookEvent(
            eventName: "PermissionRequest",
            sessionId: "claude-session",
            toolName: "Write",
            toolInput: ["file_path": "/tmp/test.swift"]
        )

        var denyCallCount = 0
        appState.permissionQueue = [
            PermissionRequest(
                event: event,
                approveAction: { _ in },
                denyAction: {
                    denyCallCount += 1
                }
            )
        ]

        appState.denyPermission()

        XCTAssertEqual(denyCallCount, 1)
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        if case .idle = appState.sessions["claude-session"]?.status {
        } else {
            XCTFail("Expected non-codex session to become idle after deny")
        }
        XCTAssertNil(appState.sessions["claude-session"]?.currentTool)
        XCTAssertNil(appState.sessions["claude-session"]?.toolDescription)
    }
}
