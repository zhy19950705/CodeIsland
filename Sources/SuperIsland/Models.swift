import Foundation
import SuperIslandCore

final class BlockingResponse {
    private var continuation: CheckedContinuation<Data, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Data, Never>) {
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: data)
    }
}

struct ApprovalPreviewPayload {
    let tool: String
    let toolInput: [String: Any]?
}

struct PermissionRequest {
    let id = UUID()
    let event: HookEvent
    let response: BlockingResponse?
    let approveAction: (@MainActor (_ always: Bool) -> Void)?
    let denyAction: (@MainActor () -> Void)?

    init(
        event: HookEvent,
        continuation: CheckedContinuation<Data, Never>,
        approveAction: (@MainActor (_ always: Bool) -> Void)? = nil,
        denyAction: (@MainActor () -> Void)? = nil
    ) {
        self.event = event
        self.response = BlockingResponse(continuation)
        self.approveAction = approveAction
        self.denyAction = denyAction
    }

    init(
        event: HookEvent,
        approveAction: @escaping @MainActor (_ always: Bool) -> Void,
        denyAction: @escaping @MainActor () -> Void
    ) {
        self.event = event
        self.response = nil
        self.approveAction = approveAction
        self.denyAction = denyAction
    }
}

struct QuestionRequest {
    let id = UUID()
    let event: HookEvent
    let question: QuestionPayload
    let response: BlockingResponse?
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
        self.response = BlockingResponse(continuation)
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
        self.response = nil
        self.answerAction = answerAction
        self.skipAction = skipAction
        self.isFromPermission = isFromPermission
    }
}
