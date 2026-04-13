import XCTest
import SuperIslandCore
@testable import SuperIsland

final class NotchPanelViewUsageTests: XCTestCase {
    func testCompactUsageProviderFollowsClaudeSessionSource() {
        var claudeSession = SessionSnapshot()
        claudeSession.source = "claude"

        let provider = NotchPanelView.compactUsageProvider(
            from: UsageSnapshot(providers: [
                makeProvider(source: .claude, percentage: 34),
                makeProvider(source: .codex, percentage: 66),
            ]),
            sessions: ["claude-session": claudeSession],
            rotatingSessionId: nil,
            activeSessionId: "claude-session",
            primarySource: "codex"
        )

        XCTAssertEqual(provider?.source, .claude)
    }

    func testPrimaryRemainingPercentageNormalizesClaudeAndCodex() {
        let claude = makeProvider(source: .claude, percentage: 34)
        XCTAssertEqual(claude.primaryUsedPercentage, 34)
        XCTAssertEqual(claude.primaryRemainingPercentage, 66)

        let codex = makeProvider(source: .codex, percentage: 66)
        XCTAssertEqual(codex.primaryUsedPercentage, 34)
        XCTAssertEqual(codex.primaryRemainingPercentage, 66)
    }

    private func makeProvider(source: UsageProviderSource, percentage: Int) -> UsageProviderSnapshot {
        UsageProviderSnapshot(
            source: source,
            primary: UsageWindowStat(
                label: "5h",
                percentage: percentage,
                detail: "2h",
                tintHex: "#2FD86D"
            ),
            secondary: UsageWindowStat(
                label: "7d",
                percentage: percentage,
                detail: "3d",
                tintHex: "#2FD86D"
            ),
            updatedAtUnix: nil,
            summary: nil,
            monthly: nil,
            history: nil
        )
    }
}
