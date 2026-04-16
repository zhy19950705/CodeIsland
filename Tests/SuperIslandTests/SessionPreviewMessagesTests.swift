import XCTest
@testable import SuperIsland
import SuperIslandCore

final class SessionPreviewMessagesTests: XCTestCase {
    func testLatestConversationPreviewMessagesKeepsOnlyLatestTurn() {
        var session = SessionSnapshot()
        session.lastUserPrompt = "最新问题"
        session.lastAssistantMessage = "最新回答"
        session.recentMessages = [
            ChatMessage(isUser: false, text: "上一条回答"),
            ChatMessage(isUser: true, text: "最新问题"),
            ChatMessage(isUser: false, text: "最新回答"),
        ]

        let preview = session.latestConversationPreviewMessages

        XCTAssertEqual(preview.map(\.isUser), [true, false])
        XCTAssertEqual(preview.map(\.text), ["最新问题", "最新回答"])
    }

    func testLatestConversationPreviewMessagesDropsStaleAssistantReplyAfterNewPrompt() {
        var session = SessionSnapshot()
        session.status = .processing
        session.lastUserPrompt = "新的问题"
        session.lastAssistantMessage = "旧的回答"
        session.recentMessages = [
            ChatMessage(isUser: false, text: "旧的回答"),
            ChatMessage(isUser: true, text: "新的问题"),
        ]

        let preview = session.latestConversationPreviewMessages

        XCTAssertEqual(preview.map(\.isUser), [true])
        XCTAssertEqual(preview.map(\.text), ["新的问题"])
    }

    func testLatestConversationPreviewMessagesPrefersRicherRecentAssistantReply() {
        var session = SessionSnapshot()
        session.lastUserPrompt = "可以"
        session.lastAssistantMessage = "已经接上原生 fallback，不依赖 codexbar。"
        session.recentMessages = [
            ChatMessage(isUser: true, text: "可以"),
            ChatMessage(
                isUser: false,
                text: """
                已经接上原生 fallback，不依赖 codexbar。
                现在 Claude 用量抓取顺序是：
                1. 原生 source
                2. 本地缓存
                """
            ),
        ]

        let preview = session.latestConversationPreviewMessages

        XCTAssertEqual(preview.map(\.isUser), [true, false])
        XCTAssertEqual(preview[1].text, """
        已经接上原生 fallback，不依赖 codexbar。
        现在 Claude 用量抓取顺序是：
        1. 原生 source
        2. 本地缓存
        """)
    }

    func testFixedListPreviewLinesExposeSingleUserAndAssistantLine() {
        var session = SessionSnapshot()
        session.lastUserPrompt = "最新问题"
        session.lastAssistantMessage = "最新回答"
        session.recentMessages = [
            ChatMessage(isUser: true, text: "旧问题"),
            ChatMessage(isUser: false, text: "旧回答"),
            ChatMessage(isUser: true, text: "最新问题"),
            ChatMessage(isUser: false, text: "最新回答"),
        ]

        let lines = session.fixedListPreviewLines

        XCTAssertEqual(lines.userText, "最新问题")
        XCTAssertEqual(lines.assistantText, "最新回答")
    }

    func testFixedListPreviewLinesPreferRunningStatusAsAssistantLine() {
        var session = SessionSnapshot()
        session.status = .processing
        session.lastUserPrompt = "继续"
        session.currentTool = "git status --short"
        session.lastAssistantMessage = "旧回答"

        let lines = session.fixedListPreviewLines

        XCTAssertEqual(lines.userText, "继续")
        XCTAssertEqual(lines.assistantText, "git status --short")
    }
}
