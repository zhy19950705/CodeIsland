import Foundation

extension UsageWindowStat {
    // Keep the badge title compact so the settings row exposes the quota window and next refresh time together.
    func badgeTitle(
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = AppLocale.chinese,
        timeZone: TimeZone = .current
    ) -> String {
        guard let refreshAtUnix, refreshAtUnix > 0 else { return label }
        let refreshText = AutomationUsageMonitorSupport.formatRefreshTimestamp(
            timestamp: refreshAtUnix,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        return "\(label) · \(refreshText)"
    }
}
