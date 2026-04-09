import XCTest
@testable import CodeIslandCore

final class SessionSnapshotMetadataTests: XCTestCase {
    func testExtractMetadataCapturesCmuxContextFromRawPayload() {
        var sessions: [String: SessionSnapshot] = ["session-1": SessionSnapshot()]
        let event = makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": "session-1",
            "_cmux_workspace_ref": "workspace:12",
            "_cmux_surface_ref": "surface:4",
            "_cmux_pane_ref": "pane:9",
            "_cmux_socket_path": "/tmp/cmux.sock",
        ])

        extractMetadata(into: &sessions, sessionId: "session-1", event: event)

        XCTAssertEqual(sessions["session-1"]?.cmuxWorkspaceRef, "workspace:12")
        XCTAssertEqual(sessions["session-1"]?.cmuxSurfaceRef, "surface:4")
        XCTAssertEqual(sessions["session-1"]?.cmuxPaneRef, "pane:9")
        XCTAssertEqual(sessions["session-1"]?.cmuxSocketPath, "/tmp/cmux.sock")
    }

    func testExtractMetadataFallsBackToEnvForCmuxContext() {
        var sessions: [String: SessionSnapshot] = ["session-2": SessionSnapshot()]
        let event = makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": "session-2",
            "_env": [
                "CMUX_WORKSPACE_REF": "workspace:22",
                "CMUX_SURFACE_REF": "surface:3",
                "CMUX_PANE_REF": "pane:5",
                "CMUX_SOCKET_PATH": "/tmp/cmux-2.sock",
            ]
        ])

        extractMetadata(into: &sessions, sessionId: "session-2", event: event)

        XCTAssertEqual(sessions["session-2"]?.cmuxWorkspaceRef, "workspace:22")
        XCTAssertEqual(sessions["session-2"]?.cmuxSurfaceRef, "surface:3")
        XCTAssertEqual(sessions["session-2"]?.cmuxPaneRef, "pane:5")
        XCTAssertEqual(sessions["session-2"]?.cmuxSocketPath, "/tmp/cmux-2.sock")
    }

    private func makeEvent(_ json: [String: Any]) -> HookEvent {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEvent(from: data)!
    }
}
