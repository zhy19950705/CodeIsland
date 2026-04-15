import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class AppStateBlockingHookReviewTests: XCTestCase {
    private func awaitPermissionResponse(
        _ appState: AppState,
        event: HookEvent,
        afterEnqueue: (UUID) -> Void
    ) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let requestId = appState.handlePermissionRequest(event, continuation: continuation)
            afterEnqueue(requestId)
        }
    }

    private func awaitQuestionResponse(
        _ appState: AppState,
        event: HookEvent,
        afterEnqueue: (UUID?) -> Void
    ) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let requestId = appState.handleQuestion(event, continuation: continuation)
            afterEnqueue(requestId)
        }
    }

    private func awaitAskUserQuestionResponse(
        _ appState: AppState,
        event: HookEvent,
        afterEnqueue: (UUID) -> Void
    ) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let requestId = appState.handleAskUserQuestion(event, continuation: continuation)
            afterEnqueue(requestId)
        }
    }

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

        let _: Data = await awaitPermissionResponse(
            appState,
            event: HookEvent(
                eventName: "PermissionRequest",
                sessionId: "done",
                toolName: "Write",
                toolInput: ["file_path": "/tmp/project/file.swift"],
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                ]
            )
        ) { _ in
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

        let _: Data = await awaitQuestionResponse(
            appState,
            event: HookEvent(
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
            )
        ) { _ in
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

        let _: Data = await awaitAskUserQuestionResponse(
            appState,
            event: HookEvent(
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
            )
        ) { _ in
            XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
            if case .waitingQuestion = appState.sessions["done"]?.status {
            } else {
                XCTFail("Expected session to move into waitingQuestion after ask-user question")
            }
            appState.answerQuestion("Yes")
        }
    }

    func testPermissionTimeoutDeniesAndClearsQueuedRequest() async {
        let appState = AppState()

        let response: Data = await awaitPermissionResponse(
            appState,
            event: HookEvent(
                eventName: "PermissionRequest",
                sessionId: "timeout-permission",
                toolName: "Write",
                toolInput: ["file_path": "/tmp/project/file.swift"],
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                ]
            )
        ) { requestId in
            XCTAssertTrue(appState.timeoutPermissionRequest(id: requestId))
        }

        let payload = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
        let output = payload?["hookSpecificOutput"] as? [String: Any]
        let decision = output?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "deny")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertEqual(appState.sessions["timeout-permission"]?.status, .idle)
    }

    func testAskUserQuestionTimeoutDeniesUnderlyingPermission() async {
        let appState = AppState()

        let response: Data = await awaitAskUserQuestionResponse(
            appState,
            event: HookEvent(
                eventName: "PermissionRequest",
                sessionId: "timeout-question",
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
            )
        ) { requestId in
            XCTAssertTrue(appState.timeoutQuestionRequest(id: requestId))
        }

        let payload = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
        let output = payload?["hookSpecificOutput"] as? [String: Any]
        let decision = output?["decision"] as? [String: Any]
        XCTAssertEqual(output?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision?["behavior"] as? String, "deny")
        XCTAssertTrue(appState.questionQueue.isEmpty)
        XCTAssertEqual(appState.sessions["timeout-question"]?.status, .processing)
    }
}
