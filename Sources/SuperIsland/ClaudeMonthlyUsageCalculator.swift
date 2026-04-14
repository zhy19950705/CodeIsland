import Foundation

private struct ClaudeUsageAccumulator {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var totalTokens: Int = 0

    mutating func add(input: Int, cachedInput: Int, output: Int) {
        inputTokens += input
        cachedInputTokens += cachedInput
        outputTokens += output
        totalTokens += input + output
    }
}

private struct ClaudeUsageRangeDescriptor {
    var preset: UsageHistoryRangePreset
    var startDate: Date
    var endDateExclusive: Date
}

private struct ClaudeUsageEvent {
    var timestamp: Date
    var model: String
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
}

private struct ClaudeUsageRowKey: Hashable {
    var dayStartUnix: TimeInterval
    var model: String
}

enum ClaudeMonthlyUsageCalculator {
    static func loadUsageHistory(
        now: Date = Date(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) -> (monthly: UsageMonthlyStat?, history: [UsageHistoryRangeSnapshot]) {
        let ranges = usageRanges(now: now, calendar: calendar)
        let events = loadUsageEvents(
            now: now,
            fileManager: fileManager,
            calendar: calendar,
            earliestStartDate: ranges.map(\.startDate).min() ?? now.addingTimeInterval(-(30 * 24 * 60 * 60))
        )

        let history = ranges.map { descriptor in
            snapshot(for: descriptor, events: events, calendar: calendar)
        }
        .filter { !$0.rows.isEmpty }

        let monthly = monthlySummary(from: history.first(where: { $0.preset == .recent30Days }), now: now)
        return (monthly, history)
    }

    private static func usageRanges(now: Date, calendar: Calendar) -> [ClaudeUsageRangeDescriptor] {
        let startOfToday = calendar.startOfDay(for: now)
        let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let recent30DayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday

        return [
            ClaudeUsageRangeDescriptor(preset: .thisWeek, startDate: weekStart, endDateExclusive: endDateExclusive),
            ClaudeUsageRangeDescriptor(preset: .thisMonth, startDate: monthStart, endDateExclusive: endDateExclusive),
            ClaudeUsageRangeDescriptor(preset: .recent30Days, startDate: recent30DayStart, endDateExclusive: endDateExclusive),
        ]
    }

    private static func monthlySummary(from snapshot: UsageHistoryRangeSnapshot?, now: Date) -> UsageMonthlyStat? {
        guard let snapshot, snapshot.totalTokens > 0 else { return nil }
        return UsageMonthlyStat(
            label: snapshot.label ?? rangeLabel(start: now, endExclusive: now),
            totalTokens: snapshot.totalTokens,
            costUSD: snapshot.costUSD
        )
    }

    private static func snapshot(
        for descriptor: ClaudeUsageRangeDescriptor,
        events: [ClaudeUsageEvent],
        calendar: Calendar
    ) -> UsageHistoryRangeSnapshot {
        var usageByRow: [ClaudeUsageRowKey: ClaudeUsageAccumulator] = [:]

        for event in events where event.timestamp >= descriptor.startDate && event.timestamp < descriptor.endDateExclusive {
            let dayStart = calendar.startOfDay(for: event.timestamp).timeIntervalSince1970
            let key = ClaudeUsageRowKey(dayStartUnix: dayStart, model: event.model)
            var usage = usageByRow[key, default: ClaudeUsageAccumulator()]
            usage.add(input: event.inputTokens, cachedInput: event.cachedInputTokens, output: event.outputTokens)
            usageByRow[key] = usage
        }

        let rows = usageByRow.map { key, usage in
            UsageHistoryRow(
                dayStartUnix: key.dayStartUnix,
                model: key.model,
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens,
                totalTokens: usage.totalTokens,
                costUSD: nil
            )
        }
        .sorted {
            if $0.dayStartUnix != $1.dayStartUnix { return $0.dayStartUnix > $1.dayStartUnix }
            if $0.totalTokens != $1.totalTokens { return $0.totalTokens > $1.totalTokens }
            return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
        }

        return UsageHistoryRangeSnapshot(
            preset: descriptor.preset,
            label: rangeLabel(start: descriptor.startDate, endExclusive: descriptor.endDateExclusive, calendar: calendar),
            totalTokens: rows.reduce(0) { $0 + $1.totalTokens },
            costUSD: nil,
            rows: rows
        )
    }

    private static func loadUsageEvents(
        now: Date,
        fileManager: FileManager,
        calendar: Calendar,
        earliestStartDate: Date
    ) -> [ClaudeUsageEvent] {
        let roots = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/claude/projects", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true),
        ]

        var events: [ClaudeUsageEvent] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                contents.enumerateLines { line, _ in
                    guard let data = line.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let timestamp = parseTimestamp(payload["timestamp"]),
                          timestamp >= earliestStartDate else {
                        return
                    }

                    guard let message = payload["message"] as? [String: Any],
                          (message["role"] as? String) == "assistant",
                          let usage = message["usage"] as? [String: Any] else {
                        return
                    }

                    let input = intValue(usage["input_tokens"] ?? usage["prompt_tokens"])
                    let cachedInput = intValue(usage["cache_read_input_tokens"] ?? usage["cached_tokens"])
                    let output = intValue(usage["output_tokens"])
                    guard input > 0 || cachedInput > 0 || output > 0 else { return }

                    let model = nonEmptyString(message["model"]) ?? "Claude"
                    events.append(
                        ClaudeUsageEvent(
                            timestamp: timestamp,
                            model: model,
                            inputTokens: input,
                            cachedInputTokens: min(cachedInput, input),
                            outputTokens: output
                        )
                    )
                }
            }
        }

        return events
    }

    private static func rangeLabel(start: Date, endExclusive: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy/M/d"
        let endDate = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        return "\(formatter.string(from: start)) - \(formatter.string(from: endDate))"
    }

    private static func parseTimestamp(_ raw: Any?) -> Date? {
        guard let raw else { return nil }
        if let number = raw as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let stringValue = raw as? String else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stringValue) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: stringValue)
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, let value = Int(string) { return value }
        return 0
    }

    private static func nonEmptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
