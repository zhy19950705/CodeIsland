import Foundation
import CodeIslandCore

struct ApprovalPreviewPayload {
    let tool: String
    let toolInput: [String: Any]?
}

struct PermissionRequest {
    let event: HookEvent
    let continuation: CheckedContinuation<Data, Never>?
    let approveAction: (@MainActor (_ always: Bool) -> Void)?
    let denyAction: (@MainActor () -> Void)?

    init(
        event: HookEvent,
        continuation: CheckedContinuation<Data, Never>,
        approveAction: (@MainActor (_ always: Bool) -> Void)? = nil,
        denyAction: (@MainActor () -> Void)? = nil
    ) {
        self.event = event
        self.continuation = continuation
        self.approveAction = approveAction
        self.denyAction = denyAction
    }

    init(
        event: HookEvent,
        approveAction: @escaping @MainActor (_ always: Bool) -> Void,
        denyAction: @escaping @MainActor () -> Void
    ) {
        self.event = event
        self.continuation = nil
        self.approveAction = approveAction
        self.denyAction = denyAction
    }
}

struct QuestionRequest {
    let event: HookEvent
    let question: QuestionPayload
    let continuation: CheckedContinuation<Data, Never>?
    let answerAction: (@MainActor (_ answer: String) -> Void)?
    let skipAction: (@MainActor () -> Void)?
    /// true when converted from AskUserQuestion PermissionRequest
    let isFromPermission: Bool

    init(
        event: HookEvent,
        question: QuestionPayload,
        continuation: CheckedContinuation<Data, Never>,
        isFromPermission: Bool = false,
        answerAction: (@MainActor (_ answer: String) -> Void)? = nil,
        skipAction: (@MainActor () -> Void)? = nil
    ) {
        self.event = event
        self.question = question
        self.continuation = continuation
        self.answerAction = answerAction
        self.skipAction = skipAction
        self.isFromPermission = isFromPermission
    }

    init(
        event: HookEvent,
        question: QuestionPayload,
        isFromPermission: Bool = false,
        answerAction: @escaping @MainActor (_ answer: String) -> Void,
        skipAction: @escaping @MainActor () -> Void
    ) {
        self.event = event
        self.question = question
        self.continuation = nil
        self.answerAction = answerAction
        self.skipAction = skipAction
        self.isFromPermission = isFromPermission
    }
}
