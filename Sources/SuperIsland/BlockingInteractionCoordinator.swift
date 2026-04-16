import Foundation
import SuperIslandCore

struct BlockingPresentationState: Equatable {
    let activeSessionId: String?
    let surface: IslandSurface
}

enum BlockingInteractionCoordinator {
    static func askUserQuestionPayload(from event: HookEvent) -> QuestionPayload {
        if let questions = event.toolInput?["questions"] as? [[String: Any]],
           let first = questions.first {
            let questionText = first["question"] as? String ?? "Question"
            let header = first["header"] as? String
            var optionLabels: [String]?
            var optionDescs: [String]?
            if let opts = first["options"] as? [[String: Any]] {
                optionLabels = opts.compactMap { $0["label"] as? String }
                optionDescs = opts.compactMap { $0["description"] as? String }
            }
            return QuestionPayload(
                question: questionText,
                options: optionLabels,
                descriptions: optionDescs,
                header: header
            )
        }

        let questionText = event.toolInput?["question"] as? String ?? "Question"
        var options: [String]?
        if let stringOpts = event.toolInput?["options"] as? [String] {
            options = stringOpts
        } else if let dictOpts = event.toolInput?["options"] as? [[String: Any]] {
            options = dictOpts.compactMap { $0["label"] as? String }
        }
        return QuestionPayload(question: questionText, options: options)
    }

    static func permissionAllowResponse(
        event: HookEvent,
        always: Bool
    ) -> Data {
        HookResponsePayload.permissionAllow(
            toolName: event.toolName,
            persistRule: always
        )
    }

    static func permissionDenyResponse() -> Data {
        HookResponsePayload.permissionDeny()
    }

    static func questionAnswerResponse(
        question: QuestionPayload,
        answer: String,
        isFromPermission: Bool
    ) -> Data {
        if isFromPermission {
            let answerKey = question.header ?? "answer"
            return HookResponsePayload.permissionAllow(answerKey: answerKey, answer: answer)
        }

        return HookResponsePayload.notificationAnswer(answer)
    }

    static func questionSkipResponse(isFromPermission: Bool) -> Data {
        if isFromPermission {
            return permissionDenyResponse()
        }
        return HookResponsePayload.notificationAck()
    }

    static func nextPresentation(
        permissionQueue: [PermissionRequest],
        questionQueue: [QuestionRequest],
        currentSurface: IslandSurface
    ) -> BlockingPresentationState? {
        if let next = permissionQueue.first {
            let sessionId = next.event.sessionId ?? "default"
            return BlockingPresentationState(
                activeSessionId: sessionId,
                surface: .approvalCard(sessionId: sessionId)
            )
        }

        if let next = questionQueue.first {
            let sessionId = next.event.sessionId ?? "default"
            return BlockingPresentationState(
                activeSessionId: sessionId,
                surface: .questionCard(sessionId: sessionId)
            )
        }

        switch currentSurface {
        case .approvalCard, .questionCard:
            return BlockingPresentationState(activeSessionId: nil, surface: .collapsed)
        case .collapsed, .sessionList, .completionCard:
            return nil
        case .sessionDetail(let sessionId):
            return BlockingPresentationState(activeSessionId: sessionId, surface: currentSurface)
        }
    }

    static func statusAfterPermissionResolution(
        source: String?,
        approved: Bool
    ) -> AgentStatus {
        if approved {
            return source == "codex" ? .processing : .running
        }
        return source == "codex" ? .processing : .idle
    }

    static func statusAfterQuestionResolution() -> AgentStatus {
        .processing
    }
}
