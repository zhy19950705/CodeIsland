import XCTest
@testable import SuperIsland

@MainActor
final class CodexInteractionCoordinatorTests: XCTestCase {
    func testPermissionInteractionBuildsPermissionEvent() {
        let note = Notification(
            name: .superIslandCodexPermissionRequested,
            object: nil,
            userInfo: [
                "threadId": "thread-1",
                "toolName": "Write",
                "prompt": "Need approval",
                "toolInput": [
                    "cwd": "/tmp/project",
                    "file_path": "/tmp/project/file.swift",
                ],
            ]
        )

        let interaction = CodexInteractionCoordinator.permissionInteraction(from: note, requestRefresh: {})

        XCTAssertEqual(interaction?.threadId, "thread-1")
        XCTAssertEqual(interaction?.event.eventName, "PermissionRequest")
        XCTAssertEqual(interaction?.event.toolName, "Write")
        XCTAssertEqual(interaction?.event.rawJSON["cwd"] as? String, "/tmp/project")
        XCTAssertEqual(interaction?.event.rawJSON["message"] as? String, "Need approval")
    }

    func testQuestionInteractionBuildsQuestionPayload() {
        let note = Notification(
            name: .superIslandCodexQuestionRequested,
            object: nil,
            userInfo: [
                "threadId": "thread-2",
                "prompt": "Ship it?",
                "header": "answer",
                "options": ["Yes", "No"],
                "descriptions": ["Proceed", "Stop"],
            ]
        )

        let interaction = CodexInteractionCoordinator.questionInteraction(from: note, requestRefresh: {})

        XCTAssertEqual(interaction?.threadId, "thread-2")
        XCTAssertEqual(interaction?.event.eventName, "AskUserQuestion")
        XCTAssertEqual(interaction?.event.toolName, "requestUserInput")
        XCTAssertEqual(interaction?.request.question.header, "answer")
        XCTAssertEqual(interaction?.request.question.options ?? [], ["Yes", "No"])
        XCTAssertEqual(interaction?.request.question.descriptions ?? [], ["Proceed", "Stop"])
    }

    func testRefreshThreadIdTrimsWhitespace() {
        let note = Notification(
            name: .superIslandCodexThreadRefreshRequested,
            object: nil,
            userInfo: [
                "threadId": "  thread-3  ",
            ]
        )

        XCTAssertEqual(CodexInteractionCoordinator.refreshThreadId(from: note), "thread-3")
    }
}
