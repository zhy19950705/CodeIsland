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

    func testCollapsedPanelWidthKeepsCompactNotchModeWideEnoughForStatusAndCounters() {
        let width = NotchPanelView.collapsedPanelWidth(
            notchWidth: 184,
            compactWingWidth: 41,
            screenWidth: 1512,
            hasNotch: true,
            displayedToolStatus: true,
            activityExtraWidth: 0
        )

        XCTAssertEqual(width, 460, accuracy: 0.001)
    }

    func testCollapsedPanelWidthHonorsMaximumWidthClamp() {
        let width = NotchPanelView.collapsedPanelWidth(
            notchWidth: 260,
            compactWingWidth: 41,
            screenWidth: 430,
            hasNotch: true,
            displayedToolStatus: true,
            activityExtraWidth: 120
        )

        XCTAssertEqual(width, 390, accuracy: 0.001)
    }

    func testSessionListNotchScrollHeightKeepsMinimumViewportForTwoRows() {
        XCTAssertEqual(SessionListView.notchScrollHeight(maxVisibleSessions: 0), 180, accuracy: 0.001)
        XCTAssertEqual(SessionListView.notchScrollHeight(maxVisibleSessions: 5), 450, accuracy: 0.001)
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
