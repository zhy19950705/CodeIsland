import XCTest
@testable import SuperIsland

// The tests lock down the preview affordances we rely on after switching to a package-backed Markdown renderer.
final class SkillMarkdownHTMLRendererTests: XCTestCase {
    func testRenderBlocksBuildsTableAndCodeBlockHTML() {
        let markdown = """
        # Title

        | 场景 | 入口 |
        | --- | --- |
        | 查询环境 | cluster-manager |

        ```python
        print("ok")
        ```
        """

        let html = SkillMarkdownHTMLRenderer.document(for: markdown)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<div class=\"table-scroll\" tabindex=\"0\"><table>"))
        XCTAssertTrue(html.contains("<th>场景</th>"))
        XCTAssertTrue(html.contains("<td>cluster-manager</td>"))
        XCTAssertTrue(html.contains("<div class=\"code-toolbar\">"))
        XCTAssertTrue(html.contains("<button class=\"copy-button\" type=\"button\">Copy</button>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-python\">"))
        XCTAssertTrue(html.contains("print(&quot;ok&quot;)"))
    }

    func testRenderBlocksKeepsListAndBlockquoteStructure() {
        let markdown = """
        > 注意先确认环境

        - 查询日志
        - 读取任务详情
        """

        let html = SkillMarkdownHTMLRenderer.document(for: markdown)

        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>查询日志</li>"))
        XCTAssertTrue(html.contains("<li>读取任务详情</li>"))
    }

    func testRenderInlineKeepsLinksAndCodeSpansSeparated() {
        let html = SkillMarkdownHTMLRenderer.renderInline("看 [文档](https://example.com) 和 `userId`")

        XCTAssertTrue(html.contains("<a href=\"https://example.com\">文档</a>"))
        XCTAssertTrue(html.contains("<code>userId</code>"))
    }

    func testRenderHTMLFragmentDecoratesExistingCodeBlocks() {
        let html = SkillMarkdownHTMLRenderer.document(
            forHTML: "<h2>Install</h2><pre><code class=\"language-bash\">echo hello</code></pre>"
        )

        XCTAssertTrue(html.contains("<h2>Install</h2>"))
        XCTAssertTrue(html.contains("<div class=\"code-toolbar\">"))
        XCTAssertTrue(html.contains("language-bash"))
        XCTAssertTrue(html.contains("echo hello"))
    }
}
