import Foundation

// Keep pure formatting and normalization logic out of the network-heavy monitor so it can be tested directly.
enum AutomationUsageMonitorSupport {
    static func codexWindowDetail(
        resetAtUnix: Int,
        resetAfterSeconds: Int,
        now: Date = Date()
    ) -> String {
        if resetAtUnix > 0 {
            return formatResetDeadline(timestamp: resetAtUnix, now: now)
        }
        if resetAfterSeconds > 0 {
            return formatResetDeadline(
                timestamp: Int(now.timeIntervalSince1970) + resetAfterSeconds,
                now: now
            )
        }
        return "--"
    }

    static func claudeWindowDetail(resetAt: TimeInterval?, now: Date = Date()) -> String {
        guard let resetAt else { return "--" }
        return formatDuration(seconds: Int(resetAt - now.timeIntervalSince1970))
    }

    static func formatDuration(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let days = clamped / (24 * 60 * 60)
        let hours = (clamped % (24 * 60 * 60)) / (60 * 60)
        let minutes = (clamped % (60 * 60)) / 60

        if days > 0 { return "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h\(String(format: "%02d", minutes))m" : "\(hours)h" }
        return "\(max(minutes, 0))m"
    }

    static func formatResetDeadline(
        timestamp: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard timestamp > 0 else { return "--" }

        let formatter = DateFormatter()
        let target = Date(timeIntervalSince1970: TimeInterval(timestamp))

        if calendar.isDateInToday(target) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: target)
        }

        let currentYear = calendar.component(.year, from: now)
        let targetYear = calendar.component(.year, from: target)
        formatter.dateFormat = currentYear == targetYear ? "M/d" : "yyyy-MM-dd"
        return formatter.string(from: target)
    }

    static func parseTimestamp(_ raw: Any?) -> TimeInterval? {
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        guard var stringValue = raw as? String else { return nil }
        stringValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stringValue.isEmpty else { return nil }

        if let unix = TimeInterval(stringValue) {
            return unix
        }

        if stringValue.hasSuffix("Z") {
            stringValue = String(stringValue.dropLast()) + "+00:00"
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stringValue) {
            return date.timeIntervalSince1970
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: stringValue)?.timeIntervalSince1970
    }

    static func integerValue(_ raw: Any?) -> Int {
        if let value = raw as? NSNumber { return value.intValue }
        if let stringValue = raw as? String, let value = Int(stringValue) { return value }
        return 0
    }

    static func doubleValue(_ raw: Any?) -> Double {
        if let value = raw as? NSNumber { return value.doubleValue }
        if let stringValue = raw as? String, let value = Double(stringValue) { return value }
        return 0
    }

    static func normalizedClaudeUtilization(_ raw: Any?) -> Double {
        let value = doubleValue(raw)
        guard value > 1 else { return value }
        return value / 100
    }

    static func clampPercentage(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    static func tintHex(forUsedPercentage value: Int) -> String {
        if value >= 90 { return "#FF6F61" }
        if value >= 70 { return "#FFAC3B" }
        return "#2FD86D"
    }

    static func tintHex(forRemainingPercentage value: Int) -> String {
        if value <= 10 { return "#FF6F61" }
        if value <= 30 { return "#FFAC3B" }
        return "#2FD86D"
    }

    static func formatTokenCount(_ totalTokens: Int) -> String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(totalTokens) / 1_000_000)
        }
        if totalTokens >= 1_000 {
            return String(format: "%.1fK tokens", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens) tokens"
    }

    static func codexUsageSummary(payload: [String: Any]) -> String? {
        var parts: [String] = []

        if let planType = nonEmptyString(payload["plan_type"]) {
            parts.append(planType.uppercased())
        }

        if let credits = payload["credits"] as? [String: Any] {
            let balance = nonEmptyString(credits["balance"])
            let hasCredits = (credits["has_credits"] as? Bool) == true
            let unlimited = (credits["unlimited"] as? Bool) == true

            if unlimited {
                parts.append("Credits unlimited")
            } else if hasCredits, let balance {
                parts.append("Credits \(balance)")
            }
        }

        if let spendControl = payload["spend_control"] as? [String: Any],
           let reached = spendControl["reached"] as? Bool {
            parts.append(reached ? "Spend blocked" : "Spend OK")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func normalizedCursorPercent(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        return clampPercentage(Int(doubleValue(raw).rounded()))
    }

    static func resolvedCursorTotalPercent(
        plan: [String: Any]?,
        autoPercent: Int?,
        apiPercent: Int?
    ) -> Int {
        if let total = normalizedCursorPercent(plan?["totalPercentUsed"]) {
            return total
        }

        if let autoPercent, let apiPercent {
            return clampPercentage(Int((Double(autoPercent + apiPercent) / 2).rounded()))
        }

        if let apiPercent { return apiPercent }
        if let autoPercent { return autoPercent }

        let used = doubleValue(plan?["used"])
        let limit = doubleValue(plan?["limit"])
        guard limit > 0 else { return 0 }
        return clampPercentage(Int(((used / limit) * 100).rounded()))
    }

    static func cursorResetDetail(resetAt: TimeInterval?, now: Date = Date()) -> String {
        guard let resetAt else { return "--" }
        return "Resets \(formatResetDeadline(timestamp: Int(resetAt), now: now))"
    }

    static func cursorUsageSummary(
        payload: [String: Any],
        plan: [String: Any]?,
        individualOnDemand: [String: Any]?,
        teamOnDemand: [String: Any]?,
        userInfo: [String: Any]?,
        sourceLabel: String,
        apiPercent: Int?
    ) -> String? {
        var parts: [String] = ["Cursor Web API via \(sourceLabel)"]

        if let membershipType = nonEmptyString(payload["membershipType"]) {
            parts.append("Plan \(membershipType.capitalized)")
        }

        if let apiPercent {
            parts.append("API \(apiPercent)%")
        }

        let planUsed = doubleValue(plan?["used"]) / 100
        let planLimit = doubleValue(plan?["limit"]) / 100
        if planUsed > 0 || planLimit > 0 {
            parts.append("Included \(formatUSD(planUsed))/\(formatUSD(planLimit))")
        }

        let onDemandUsed = doubleValue(individualOnDemand?["used"]) / 100
        let onDemandLimit = doubleValue(individualOnDemand?["limit"]) / 100
        if onDemandUsed > 0 || onDemandLimit > 0 {
            let suffix = onDemandLimit > 0 ? "/\(formatUSD(onDemandLimit))" : ""
            parts.append("On-demand \(formatUSD(onDemandUsed))\(suffix)")
        }

        let teamOnDemandUsed = doubleValue(teamOnDemand?["used"]) / 100
        let teamOnDemandLimit = doubleValue(teamOnDemand?["limit"]) / 100
        if teamOnDemandUsed > 0 || teamOnDemandLimit > 0 {
            let suffix = teamOnDemandLimit > 0 ? "/\(formatUSD(teamOnDemandLimit))" : ""
            parts.append("Team \(formatUSD(teamOnDemandUsed))\(suffix)")
        }

        if let email = nonEmptyString(userInfo?["email"]) {
            parts.append(email)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func formatUSD(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func claudeQuotaSummary(sourceLabel: String, hasLocalHistory: Bool) -> String? {
        guard hasLocalHistory else { return sourceLabel == "Claude Code OAuth" ? nil : sourceLabel }
        if sourceLabel == "Claude Code OAuth" {
            return "Quota + local token history"
        }
        return "\(sourceLabel) + local token history"
    }
}
