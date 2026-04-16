import Foundation
import SuperIslandCore

/// Parses provider transcript files into timeline items for the inline panel conversation view.
actor ConversationParser {
    static let shared = ConversationParser()

    private struct CachedConversation {
        let token: ConversationCacheToken
        let items: [ConversationHistoryItem]
        let sourcePath: String
    }

    /// Cache tokens are shared across provider-specific parser files, so they cannot stay file-private.
    enum ConversationCacheToken: Equatable {
        case file(modifiedAt: Date, fileSize: UInt64)
        case fallback(String)
    }

    private var cache: [String: CachedConversation] = [:]

    /// Returns both the parsed items and the backing source path for UI diagnostics.
    func parseHistory(sessionId: String, session: SessionSnapshot) async -> SessionConversationState {
        switch session.source {
        case "claude":
            return await parseClaudeConversation(sessionId: sessionId, session: session)
        case "codex":
            return parseCodexConversation(sessionId: sessionId, session: session)
        default:
            return fallbackConversationState(sessionId: sessionId, session: session)
        }
    }

    /// Clearing one session avoids stale transcript rendering when files rotate or are deleted.
    func invalidate(sessionId: String) {
        cache.removeValue(forKey: sessionId)
    }

    func invalidateAll() {
        cache.removeAll()
    }

    /// Lightweight cache token uses metadata only, which keeps repeat panel opens cheap.
    func cachedState(
        sessionId: String,
        token: ConversationCacheToken,
        sourcePath: String
    ) -> SessionConversationState? {
        guard let cached = cache[sessionId],
              cached.token == token,
              cached.sourcePath == sourcePath else {
            return nil
        }
        return SessionConversationState(items: cached.items, isLoading: false, errorText: nil, sourcePath: sourcePath)
    }

    func storeCache(
        sessionId: String,
        token: ConversationCacheToken,
        sourcePath: String,
        items: [ConversationHistoryItem]
    ) -> SessionConversationState {
        cache[sessionId] = CachedConversation(token: token, items: items, sourcePath: sourcePath)
        return SessionConversationState(items: items, isLoading: false, errorText: nil, sourcePath: sourcePath)
    }

    /// Sessions without a structured transcript still fall back to recent preview messages.
    func fallbackConversationState(sessionId: String, session: SessionSnapshot) -> SessionConversationState {
        let items = session.latestConversationPreviewMessages.enumerated().map { index, message in
            ConversationHistoryItem(
                id: "\(sessionId)-fallback-\(index)",
                kind: message.isUser ? .user(message.text) : .assistant(message.text),
                timestamp: session.lastActivity
            )
        }
        let token = ConversationCacheToken.fallback("\(session.lastActivity.timeIntervalSince1970)")
        return storeCache(sessionId: sessionId, token: token, sourcePath: session.cwd ?? session.source, items: items)
    }
}
