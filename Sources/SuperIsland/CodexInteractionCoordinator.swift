import Foundation
import SuperIslandCore

struct CodexPermissionInteraction {
    let threadId: String
    let event: HookEvent
    let request: PermissionRequest
}

struct CodexQuestionInteraction {
    let threadId: String
    let event: HookEvent
    let request: QuestionRequest
}

enum CodexInteractionCoordinator {
    static func permissionInteraction(
        from note: Notification,
        requestRefresh: @escaping @MainActor () -> Void
    ) -> CodexPermissionInteraction? {
        guard let userInfo = note.userInfo,
              let threadId = userInfo["threadId"] as? String,
              let toolName = userInfo["toolName"] as? String else { return nil }

        let prompt = nonEmpty(userInfo["prompt"] as? String)
        let stringToolInput = userInfo["toolInput"] as? [String: String]
        let toolInput = stringToolInput?.reduce(into: [String: Any]()) { partial, entry in
            partial[entry.key] = entry.value
        }
        var rawJSON: [String: Any] = ["_source": "codex"]
        if let prompt {
            rawJSON["message"] = prompt
        }
        if let cwd = nonEmpty(stringToolInput?["cwd"]) {
            rawJSON["cwd"] = cwd
        }

        let event = HookEvent(
            eventName: "PermissionRequest",
            sessionId: threadId,
            toolName: toolName,
            toolInput: toolInput,
            rawJSON: rawJSON
        )

        let request = PermissionRequest(
            event: event,
            approveAction: { always in
                Task {
                    await CodexAppServerClient.shared.approve(threadId: threadId, forSession: always)
                    await MainActor.run {
                        requestRefresh()
                    }
                }
            },
            denyAction: {
                Task {
                    await CodexAppServerClient.shared.deny(threadId: threadId)
                    await MainActor.run {
                        requestRefresh()
                    }
                }
            }
        )

        return CodexPermissionInteraction(threadId: threadId, event: event, request: request)
    }

    static func questionInteraction(
        from note: Notification,
        requestRefresh: @escaping @MainActor () -> Void
    ) -> CodexQuestionInteraction? {
        guard let userInfo = note.userInfo,
              let threadId = userInfo["threadId"] as? String,
              let prompt = userInfo["prompt"] as? String else { return nil }

        let options = userInfo["options"] as? [String]
        let descriptions = userInfo["descriptions"] as? [String]
        let header = nonEmpty(userInfo["header"] as? String)
        var toolInput: [String: Any] = ["question": prompt]
        if let options {
            toolInput["options"] = options
        }
        if let header {
            toolInput["header"] = header
        }
        var rawJSON: [String: Any] = [
            "_source": "codex",
            "question": prompt,
        ]
        if let options {
            rawJSON["options"] = options
        }

        let event = HookEvent(
            eventName: "AskUserQuestion",
            sessionId: threadId,
            toolName: "requestUserInput",
            toolInput: toolInput,
            rawJSON: rawJSON
        )
        let payload = QuestionPayload(
            question: prompt,
            options: options,
            descriptions: descriptions,
            header: header
        )

        let request = QuestionRequest(
            event: event,
            question: payload,
            isFromPermission: false,
            answerAction: { answer in
                Task {
                    await CodexAppServerClient.shared.answer(threadId: threadId, answer: answer)
                    await MainActor.run {
                        requestRefresh()
                    }
                }
            },
            skipAction: {
                Task {
                    await CodexAppServerClient.shared.skipQuestion(threadId: threadId)
                    await MainActor.run {
                        requestRefresh()
                    }
                }
            }
        )

        return CodexQuestionInteraction(threadId: threadId, event: event, request: request)
    }

    static func refreshThreadId(from note: Notification) -> String? {
        nonEmpty(note.userInfo?["threadId"] as? String)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
