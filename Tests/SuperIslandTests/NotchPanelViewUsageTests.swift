import XCTest
import SuperIslandCore
@testable import SuperIsland

final class NotchPanelViewUsageTests: XCTestCase {
    func testHideWhenNoSessionOnlyHidesWhenSessionStoreIsEmpty() {
        XCTAssertTrue(
            SessionVisibilityPolicy.shouldHideWhenNoSession(
                hideWhenNoSession: true,
                sessions: [:]
            )
        )

        var historicalSession = SessionSnapshot()
        historicalSession.source = "codex"
        historicalSession.isHistoricalSnapshot = true

        XCTAssertFalse(
            SessionVisibilityPolicy.shouldHideWhenNoSession(
                hideWhenNoSession: true,
                sessions: ["history": historicalSession]
            )
        )
    }

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

        let cursor = makeProvider(source: .cursor, percentage: 12)
        XCTAssertEqual(cursor.primaryUsedPercentage, 12)
        XCTAssertEqual(cursor.primaryRemainingPercentage, 88)

        let codex = makeProvider(source: .codex, percentage: 66)
        XCTAssertEqual(codex.primaryUsedPercentage, 34)
        XCTAssertEqual(codex.primaryRemainingPercentage, 66)
    }

    func testCompactUsageProviderFollowsCursorSessionSource() {
        var cursorSession = SessionSnapshot()
        cursorSession.source = "cursor"

        let provider = NotchPanelView.compactUsageProvider(
            from: UsageSnapshot(providers: [
                makeProvider(source: .cursor, percentage: 21),
                makeProvider(source: .codex, percentage: 66),
            ]),
            sessions: ["cursor-session": cursorSession],
            rotatingSessionId: nil,
            activeSessionId: "cursor-session",
            primarySource: "codex"
        )

        XCTAssertEqual(provider?.source, .cursor)
    }

    func testCompactUsageProviderSkipsTokenOnlyClaudeSnapshot() {
        var claudeSession = SessionSnapshot()
        claudeSession.source = "claude"

        let provider = NotchPanelView.compactUsageProvider(
            from: UsageSnapshot(providers: [
                makeProvider(source: .claude, percentage: 0, showsQuotaBadge: false),
            ]),
            sessions: ["claude-session": claudeSession],
            rotatingSessionId: nil,
            activeSessionId: "claude-session",
            primarySource: "claude"
        )

        XCTAssertNil(provider)
    }

    func testClaudePrimaryUsagePreservesFiveHourWindowWhenZeroUsed() {
        let provider = UsageProviderSnapshot(
            source: .claude,
            primary: UsageWindowStat(
                label: "5h",
                percentage: 0,
                detail: "--",
                tintHex: "#2FD86D"
            ),
            secondary: UsageWindowStat(
                label: "7d",
                percentage: 53,
                detail: "10h",
                tintHex: "#2FD86D"
            ),
            updatedAtUnix: nil,
            summary: nil,
            monthly: nil,
            history: nil,
            showsQuotaBadge: true
        )

        XCTAssertEqual(provider.usedPercentage(for: provider.primary), 0)
        XCTAssertEqual(provider.remainingPercentage(for: provider.primary), 100)
    }

    private func makeProvider(
        source: UsageProviderSource,
        percentage: Int,
        showsQuotaBadge: Bool? = true
    ) -> UsageProviderSnapshot {
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
            history: nil,
            showsQuotaBadge: showsQuotaBadge
        )
    }
}
