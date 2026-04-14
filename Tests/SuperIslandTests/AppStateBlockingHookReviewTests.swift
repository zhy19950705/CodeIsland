import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class AppStateBlockingHookReviewTests: XCTestCase {
    func testPermissionRequestClearsPendingCompletionReview() async {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))

        let _: Data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            appState.handlePermissionRequest(
                HookEvent(
                    eventName: "PermissionRequest",
                    sessionId: "done",
                    toolName: "Write",
                    toolInput: ["file_path": "/tmp/project/file.swift"],
                    rawJSON: [
                        "_source": "claude",
                        "cwd": "/tmp/project",
                    ]
                ),
                continuation: continuation
            )
            XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
            if case .waitingApproval = appState.sessions["done"]?.status {
            } else {
                XCTFail("Expected session to move into waitingApproval after permission request")
            }
            appState.denyPermission()
        }
    }

    func testQuestionRequestClearsPendingCompletionReview() async {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))

        let _: Data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            appState.handleQuestion(
                HookEvent(
                    eventName: "Notification",
                    sessionId: "done",
                    toolName: nil,
                    toolInput: nil,
                    rawJSON: [
                        "_source": "claude",
                        "cwd": "/tmp/project",
                        "question": "Ship it?",
                        "options": ["Yes", "No"],
                    ]
                ),
                continuation: continuation
            )
            XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
            if case .waitingQuestion = appState.sessions["done"]?.status {
            } else {
                XCTFail("Expected session to move into waitingQuestion after question request")
            }
            appState.answerQuestion("Yes")
        }
    }

    func testAskUserQuestionClearsPendingCompletionReview() async {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))

        let _: Data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            appState.handleAskUserQuestion(
                HookEvent(
                    eventName: "PermissionRequest",
                    sessionId: "done",
                    toolName: "AskUserQuestion",
                    toolInput: [
                        "questions": [[
                            "header": "answer",
                            "question": "Ship it?",
                            "options": [
                                ["label": "Yes", "description": "Proceed"],
                                ["label": "No", "description": "Stop"],
                            ],
                        ]],
                    ],
                    rawJSON: [
                        "_source": "claude",
                        "cwd": "/tmp/project",
                    ]
                ),
                continuation: continuation
            )
            XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
            if case .waitingQuestion = appState.sessions["done"]?.status {
            } else {
                XCTFail("Expected session to move into waitingQuestion after ask-user question")
            }
            appState.answerQuestion("Yes")
        }
    }
}
