import XCTest
@testable import SuperIsland

final class UsageWindowRefreshSupportTests: XCTestCase {
    func testBadgeTitleIncludesSameDayRefreshTime() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let calendar = makeCalendar(timeZone: timeZone)
        let locale = Locale(identifier: "en_US_POSIX")
        let now = makeDate(year: 2025, month: 4, day: 16, hour: 8, minute: 0, calendar: calendar)
        let refreshAt = makeDate(year: 2025, month: 4, day: 16, hour: 11, minute: 15, calendar: calendar)
        let window = UsageWindowStat(
            label: "5h",
            percentage: 42,
            detail: "3h15m",
            refreshAtUnix: refreshAt.timeIntervalSince1970,
            tintHex: "#2FD86D"
        )

        XCTAssertEqual(
            window.badgeTitle(now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "5h · 11:15"
        )
    }

    func testBadgeTitleIncludesDateForLaterRefresh() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let calendar = makeCalendar(timeZone: timeZone)
        let locale = Locale(identifier: "en_US_POSIX")
        let now = makeDate(year: 2025, month: 4, day: 16, hour: 8, minute: 0, calendar: calendar)
        let refreshAt = makeDate(year: 2025, month: 4, day: 19, hour: 15, minute: 50, calendar: calendar)
        let window = UsageWindowStat(
            label: "7d",
            percentage: 18,
            detail: "3d",
            refreshAtUnix: refreshAt.timeIntervalSince1970,
            tintHex: "#2FD86D"
        )

        XCTAssertEqual(
            window.badgeTitle(now: now, calendar: calendar, locale: locale, timeZone: timeZone),
            "7d · 4月19日"
        )
    }

    func testCodexWindowDetailUsesRemainingDuration() {
        let now = makeDate(
            year: 2025,
            month: 4,
            day: 16,
            hour: 8,
            minute: 0,
            calendar: makeCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        XCTAssertEqual(
            AutomationUsageMonitorSupport.codexWindowDetail(
                resetAtUnix: Int(now.timeIntervalSince1970) + 5_400,
                resetAfterSeconds: 0,
                now: now
            ),
            "1h30m"
        )
    }

    // Centralize calendar construction so the formatting assertions stay stable across developer machines.
    private func makeCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
