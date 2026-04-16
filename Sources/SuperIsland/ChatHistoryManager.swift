import Foundation
import SuperIslandCore

/// Shared conversation loader that keeps transcript parsing off the hot UI path.
@MainActor
final class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()
    static let sessionIdUserInfoKey = "sessionId"

    @Published private(set) var states: [String: SessionConversationState] = [:]

    private var loadingTasks: [String: Task<Void, Never>] = [:]

    func state(for sessionId: String) -> SessionConversationState {
        states[sessionId] ?? .empty
    }

    /// Loads or refreshes a session transcript. Repeated calls are cheap because ConversationParser caches by file metadata.
    func load(sessionId: String, session: SessionSnapshot) async {
        loadingTasks[sessionId]?.cancel()
        states[sessionId, default: .empty].isLoading = true
        states[sessionId, default: .empty].errorText = nil
        postConversationStateDidChange(sessionId: sessionId)

        let task = Task { [weak self] in
            guard let self else { return }
            let state = await ConversationParser.shared.parseHistory(sessionId: sessionId, session: session)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.states[sessionId] = state
                self.loadingTasks[sessionId] = nil
                self.postConversationStateDidChange(sessionId: sessionId)
            }
        }

        loadingTasks[sessionId] = task
        await task.value
    }

    /// Clearing cached state is useful when a session disappears or a transcript file is rotated.
    func invalidate(sessionId: String) {
        loadingTasks[sessionId]?.cancel()
        loadingTasks.removeValue(forKey: sessionId)
        states.removeValue(forKey: sessionId)
        postConversationStateDidChange(sessionId: sessionId)
        Task {
            await ConversationParser.shared.invalidate(sessionId: sessionId)
        }
    }

    func invalidateAll() {
        for key in loadingTasks.keys {
            loadingTasks[key]?.cancel()
        }
        loadingTasks.removeAll()
        states.removeAll()
        postConversationStateDidChange(sessionId: nil)
        Task {
            await ConversationParser.shared.invalidateAll()
        }
    }

    /// Broadcast transcript state changes so the floating panel can recompute its height after parsing finishes.
    private func postConversationStateDidChange(sessionId: String?) {
        var userInfo: [String: String] = [:]
        if let sessionId {
            userInfo[Self.sessionIdUserInfoKey] = sessionId
        }
        NotificationCenter.default.post(
            name: .superIslandConversationStateDidChange,
            object: self,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}

extension Notification.Name {
    static let superIslandConversationStateDidChange = Notification.Name("SuperIslandConversationStateDidChange")
}
