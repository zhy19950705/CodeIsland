import XCTest
@testable import SuperIsland

final class AutomationUsageMonitorSupportTests: XCTestCase {
    // Cover pure helper behavior directly so large monitor refactors can stay low risk.
    func testParseTimestampSupportsFractionalISO8601() throws {
        let timestamp = try XCTUnwrap(
            AutomationUsageMonitorSupport.parseTimestamp("2026-04-15T08:30:45.123Z")
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try XCTUnwrap(formatter.date(from: "2026-04-15T08:30:45.123Z"))
        let expected = expectedDate.timeIntervalSince1970

        XCTAssertEqual(timestamp, expected, accuracy: 0.001)
    }

    func testResolvedCursorTotalPercentFallsBackToAverageOfAutoAndAPI() {
        let percent = AutomationUsageMonitorSupport.resolvedCursorTotalPercent(
            plan: nil,
            autoPercent: 40,
            apiPercent: 80
        )

        XCTAssertEqual(percent, 60)
    }

    func testCodexUsageSummaryIncludesPlanCreditsAndSpendState() {
        let summary = AutomationUsageMonitorSupport.codexUsageSummary(
            payload: [
                "plan_type": "pro",
                "credits": [
                    "has_credits": true,
                    "balance": "42",
                    "unlimited": false,
                ],
                "spend_control": [
                    "reached": false,
                ],
            ]
        )

        XCTAssertEqual(summary, "PRO · Credits 42 · 支出正常")
    }

    func testClaudeQuotaSummarySuppressesDefaultOAuthLabelWithoutHistory() {
        XCTAssertNil(
            AutomationUsageMonitorSupport.claudeQuotaSummary(
                sourceLabel: "Claude Code OAuth",
                hasLocalHistory: false
            )
        )
        XCTAssertEqual(
            AutomationUsageMonitorSupport.claudeQuotaSummary(
                sourceLabel: "Claude Web API",
                hasLocalHistory: true
            ),
            "Claude Web API + 本地令牌历史"
        )
    }

    func testCursorUsageSummaryIncludesBillingSections() {
        let summary = AutomationUsageMonitorSupport.cursorUsageSummary(
            payload: ["membershipType": "pro"],
            plan: ["used": 250, "limit": 1000],
            individualOnDemand: ["used": 50, "limit": 300],
            teamOnDemand: ["used": 125, "limit": 500],
            userInfo: ["email": "dev@example.com"],
            sourceLabel: "Chrome/Profile 1",
            apiPercent: 25
        )

        XCTAssertEqual(
            summary,
            "Cursor Web API（来源：Chrome/Profile 1） · 套餐 Pro · API 25% · 套餐内 $2.50/$10.00 · 按量 $0.50/$3.00 · 团队 $1.25/$5.00 · dev@example.com"
        )
    }

    func testFormatTokenCountUsesCompactUnits() {
        XCTAssertEqual(AutomationUsageMonitorSupport.formatTokenCount(950), "950 令牌")
        XCTAssertEqual(AutomationUsageMonitorSupport.formatTokenCount(12_500), "12.5K 令牌")
        XCTAssertEqual(AutomationUsageMonitorSupport.formatTokenCount(2_500_000), "2.5M 令牌")
    }
}
