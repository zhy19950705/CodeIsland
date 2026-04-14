import Foundation
import SuperIslandCore

extension SessionSnapshot {
    var latestConversationPreviewMessages: [ChatMessage] {
        let lastVisibleUser = Self.normalizedPreviewText(lastUserPrompt)
        let lastVisibleAssistant = Self.normalizedPreviewText(lastAssistantMessage)
        let normalizedRecentMessages = recentMessages.compactMap { message -> ChatMessage? in
            guard let text = Self.normalizedPreviewText(message.text) else { return nil }
            return ChatMessage(isUser: message.isUser, text: text)
        }

        let lastUserIndex = normalizedRecentMessages.lastIndex(where: \.isUser)
        let lastAssistantIndex = normalizedRecentMessages.lastIndex(where: { !$0.isUser })

        if let lastUserIndex,
           let lastAssistantIndex,
           lastUserIndex > lastAssistantIndex {
            let recentUser = normalizedRecentMessages[lastUserIndex].text
            if let userText = Self.preferredPreviewText(primary: lastVisibleUser, secondary: recentUser) {
                return [ChatMessage(isUser: true, text: userText)]
            }
            return [normalizedRecentMessages[lastUserIndex]]
        }

        if let lastAssistantIndex {
            let recentAssistant = normalizedRecentMessages[lastAssistantIndex].text
            let recentUser: String?
            if let lastUserIndex, lastUserIndex < lastAssistantIndex {
                recentUser = normalizedRecentMessages[lastUserIndex].text
            } else {
                recentUser = nil
            }

            if let assistantText = Self.preferredPreviewText(primary: lastVisibleAssistant, secondary: recentAssistant) {
                if let userText = Self.preferredPreviewText(primary: lastVisibleUser, secondary: recentUser) {
                    return [
                        ChatMessage(isUser: true, text: userText),
                        ChatMessage(isUser: false, text: assistantText),
                    ]
                }
                return [
                    ChatMessage(isUser: false, text: assistantText),
                ]
            }
        }

        if let lastVisibleUser {
            return [ChatMessage(isUser: true, text: lastVisibleUser)]
        }

        if let lastMessage = normalizedRecentMessages.last {
            return [lastMessage]
        }

        return []
    }

    private static func normalizedPreviewText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func preferredPreviewText(primary: String?, secondary: String?) -> String? {
        let primary = normalizedPreviewText(primary)
        let secondary = normalizedPreviewText(secondary)

        switch (primary, secondary) {
        case let (value?, nil), let (nil, value?):
            return value
        case let (primary?, secondary?):
            if primary == secondary {
                return primary
            }

            let primaryCollapsed = collapsedPreviewText(primary)
            let secondaryCollapsed = collapsedPreviewText(secondary)

            if primaryCollapsed == secondaryCollapsed {
                return primary.count >= secondary.count ? primary : secondary
            }

            if secondaryCollapsed.hasPrefix(primaryCollapsed) || secondaryCollapsed.contains(primaryCollapsed) {
                return secondary
            }

            if primaryCollapsed.hasPrefix(secondaryCollapsed) || primaryCollapsed.contains(secondaryCollapsed) {
                return primary
            }

            if secondary.count > primary.count + 40,
               sharedPreviewPrefixLength(primaryCollapsed, secondaryCollapsed) >= 24 {
                return secondary
            }

            return primary
        case (nil, nil):
            return nil
        }
    }

    private static func collapsedPreviewText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sharedPreviewPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix(while: ==).count
    }
}
