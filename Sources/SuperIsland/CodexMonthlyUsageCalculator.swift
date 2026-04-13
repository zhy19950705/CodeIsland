import Foundation

private struct CodexTokenUsageDelta {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
}

private struct CodexRawUsage {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
}

private struct CodexTokenUsageEvent {
    var timestamp: Date
    var model: String
    var delta: CodexTokenUsageDelta
}

private struct CodexModelUsageAccumulator {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningOutputTokens: Int = 0
    var totalTokens: Int = 0

    mutating func add(_ delta: CodexTokenUsageDelta) {
        inputTokens += delta.inputTokens
        cachedInputTokens += delta.cachedInputTokens
        outputTokens += delta.outputTokens
        reasoningOutputTokens += delta.reasoningOutputTokens
        totalTokens += delta.totalTokens
    }
}

private struct CodexModelPricing {
    var inputCostPerToken: Double
    var cachedInputCostPerToken: Double
    var outputCostPerToken: Double
}

private struct CodexUsageRangeDescriptor {
    var preset: UsageHistoryRangePreset
    var startDate: Date
    var endDateExclusive: Date
}

private struct CodexUsageRowKey: Hashable {
    var dayStart: Date
    var model: String
}

enum CodexMonthlyUsageCalculator {
    private static let pricingURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let providerPrefixes = ["", "openai/", "azure/", "openrouter/openai/"]
    private static let modelAliases: [String: String] = [
        "gpt-5-codex": "gpt-5",
        "gpt-5.3-codex": "gpt-5.2-codex",
    ]
    private static let fallbackModel = "gpt-5"
    private static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainTimestampFormatter = ISO8601DateFormatter()

    static func loadCurrentMonth(
        now: Date = Date(),
        fileManager: FileManager = .default,
        sessionsDirectory: URL? = nil,
        pricingDataset: [String: [String: Any]]? = nil
    ) -> UsageMonthlyStat? {
        loadUsageHistory(
            now: now,
            fileManager: fileManager,
            sessionsDirectory: sessionsDirectory,
            pricingDataset: pricingDataset
        ).monthly
    }

    static func loadUsageHistory(
        now: Date = Date(),
        fileManager: FileManager = .default,
        sessionsDirectory: URL? = nil,
        pricingDataset: [String: [String: Any]]? = nil
    ) -> (monthly: UsageMonthlyStat?, history: [UsageHistoryRangeSnapshot]) {
        let calendar = Calendar.current
        let ranges = usageRanges(now: now, calendar: calendar)
        guard let earliestStartDate = ranges.map(\.startDate).min(),
              let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return (nil, [])
        }

        let baseSessionsDirectory = sessionsDirectoryURL(fileManager: fileManager, override: sessionsDirectory)
        let directories = candidateDirectories(
            startDate: earliestStartDate,
            endDate: now,
            sessionsDirectory: baseSessionsDirectory,
            calendar: calendar
        )

        let events = loadUsageEvents(
            directories: directories,
            startDate: earliestStartDate,
            endDateExclusive: endDateExclusive,
            fileManager: fileManager
        )
        guard !events.isEmpty else { return (nil, []) }

        let resolvedPricingDataset = pricingDataset ?? fetchPricingDataset()
        let history = ranges.map {
            historySnapshot(
                for: $0,
                events: events,
                pricingDataset: resolvedPricingDataset,
                calendar: calendar
            )
        }

        return (
            monthly: monthlySummary(from: history.first(where: { $0.preset == .recent30Days }), now: now),
            history: history
        )
    }

    private static func usageRanges(now: Date, calendar: Calendar) -> [CodexUsageRangeDescriptor] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
        let recent30DayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        return [
            CodexUsageRangeDescriptor(preset: .thisWeek, startDate: startOfWeek, endDateExclusive: endDateExclusive),
            CodexUsageRangeDescriptor(preset: .thisMonth, startDate: startOfMonth, endDateExclusive: endDateExclusive),
            CodexUsageRangeDescriptor(preset: .recent30Days, startDate: recent30DayStart, endDateExclusive: endDateExclusive),
        ]
    }

    private static func monthlySummary(from snapshot: UsageHistoryRangeSnapshot?, now: Date) -> UsageMonthlyStat? {
        guard let snapshot, snapshot.totalTokens > 0 else { return nil }
        return UsageMonthlyStat(
            label: recent30DayLabel(endingAt: now),
            totalTokens: snapshot.totalTokens,
            costUSD: snapshot.costUSD
        )
    }

    private static func recent30DayLabel(endingAt date: Date) -> String {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: date)) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: date))"
    }

    private static func rangeLabel(
        startDate: Date,
        endDateExclusive: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let inclusiveEnd = endDateExclusive.addingTimeInterval(-1)
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: inclusiveEnd))"
    }

    private static func historySnapshot(
        for descriptor: CodexUsageRangeDescriptor,
        events: [CodexTokenUsageEvent],
        pricingDataset: [String: [String: Any]],
        calendar: Calendar
    ) -> UsageHistoryRangeSnapshot {
        var usageByRow: [CodexUsageRowKey: CodexModelUsageAccumulator] = [:]

        for event in events where event.timestamp >= descriptor.startDate && event.timestamp < descriptor.endDateExclusive {
            let key = CodexUsageRowKey(
                dayStart: calendar.startOfDay(for: event.timestamp),
                model: event.model
            )
            var usage = usageByRow[key, default: CodexModelUsageAccumulator()]
            usage.add(event.delta)
            usageByRow[key] = usage
        }

        var totalCostUSD = 0.0
        var hasCost = false
        var rows: [UsageHistoryRow] = []

        for (key, usage) in usageByRow {
            let costUSD = resolvePricing(for: key.model, dataset: pricingDataset).map {
                let cost = calculateCostUSD(usage: usage, pricing: $0)
                hasCost = true
                totalCostUSD += cost
                return cost
            }

            rows.append(
                UsageHistoryRow(
                    dayStartUnix: key.dayStart.timeIntervalSince1970,
                    model: key.model,
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    outputTokens: usage.outputTokens,
                    totalTokens: usage.totalTokens,
                    costUSD: costUSD
                )
            )
        }

        rows.sort {
            if $0.dayStartUnix != $1.dayStartUnix {
                return $0.dayStartUnix > $1.dayStartUnix
            }
            if $0.totalTokens != $1.totalTokens {
                return $0.totalTokens > $1.totalTokens
            }
            return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
        }

        return UsageHistoryRangeSnapshot(
            preset: descriptor.preset,
            label: rangeLabel(startDate: descriptor.startDate, endDateExclusive: descriptor.endDateExclusive),
            totalTokens: rows.reduce(0) { $0 + $1.totalTokens },
            costUSD: hasCost ? totalCostUSD : nil,
            rows: rows
        )
    }

    private static func sessionsDirectoryURL(fileManager: FileManager, override: URL?) -> URL {
        if let override { return override }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func candidateDirectories(
        startDate: Date,
        endDate: Date,
        sessionsDirectory: URL,
        calendar: Calendar
    ) -> [URL] {
        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate

        var directories: [URL] = []
        var cursor = startMonth
        while cursor <= endMonth {
            let components = calendar.dateComponents([.year, .month], from: cursor)
            let year = String(format: "%04d", components.year ?? 0)
            let month = String(format: "%02d", components.month ?? 0)
            directories.append(
                sessionsDirectory
                    .appendingPathComponent(year, isDirectory: true)
                    .appendingPathComponent(month, isDirectory: true)
            )
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
        }
        return directories
    }

    private static func loadUsageEvents(
        directories: [URL],
        startDate: Date,
        endDateExclusive: Date,
        fileManager: FileManager
    ) -> [CodexTokenUsageEvent] {
        if let ripgrepEvents = loadEventsWithRipgrep(
            directories: directories,
            startDate: startDate,
            endDateExclusive: endDateExclusive
        ) {
            return ripgrepEvents
        }

        var events: [CodexTokenUsageEvent] = []
        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
                if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modifiedAt = values.contentModificationDate,
                   modifiedAt < startDate {
                    continue
                }

                events.append(
                    contentsOf: loadEvents(
                        from: fileURL,
                        startDate: startDate,
                        endDateExclusive: endDateExclusive
                    )
                )
            }
        }

        return events
    }

    private static func loadEventsWithRipgrep(
        directories: [URL],
        startDate: Date,
        endDateExclusive: Date
    ) -> [CodexTokenUsageEvent]? {
        let existingDirectories = directories.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingDirectories.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "rg",
            "--no-heading",
            "-n",
            "\"type\":\"turn_context\"|\"type\":\"token_count\"",
        ] + existingDirectories.map(\.path) + ["-g", "*.jsonl"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }

        guard !output.isEmpty else { return [] }

        var matchesByFile: [String: [(lineNumber: Int, json: String)]] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let jsonlRange = line.range(of: ".jsonl:") else { continue }
            let filePath = String(line[..<jsonlRange.upperBound]).dropLast()
            let remainder = line[jsonlRange.upperBound...]
            guard let separator = remainder.firstIndex(of: ":"),
                  let lineNumber = Int(remainder[..<separator]) else {
                continue
            }
            let json = String(remainder[remainder.index(after: separator)...])
            matchesByFile[String(filePath), default: []].append((lineNumber, json))
        }

        var events: [CodexTokenUsageEvent] = []
        for (filePath, matches) in matchesByFile {
            let sortedMatches = matches.sorted { $0.lineNumber < $1.lineNumber }
            events.append(
                contentsOf: loadEvents(
                    fromMatchedLines: sortedMatches.map(\.json),
                    fileURL: URL(fileURLWithPath: filePath),
                    startDate: startDate,
                    endDateExclusive: endDateExclusive
                )
            )
        }
        return events
    }

    private static func loadEvents(
        from fileURL: URL,
        startDate: Date,
        endDateExclusive: Date
    ) -> [CodexTokenUsageEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return loadEvents(
            fromMatchedLines: content.split(whereSeparator: \.isNewline).map(String.init),
            fileURL: fileURL,
            startDate: startDate,
            endDateExclusive: endDateExclusive
        )
    }

    private static func loadEvents(
        fromMatchedLines lines: [String],
        fileURL: URL,
        startDate: Date,
        endDateExclusive: Date
    ) -> [CodexTokenUsageEvent] {
        _ = fileURL

        var events: [CodexTokenUsageEvent] = []
        var previousTotals: CodexRawUsage?
        var currentModel: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                continue
            }

            if type == "turn_context" {
                if let payload = object["payload"] {
                    currentModel = extractModel(from: payload) ?? currentModel
                }
                continue
            }

            guard type == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let timestampRaw = object["timestamp"] as? String,
                  let timestamp = parseTimestamp(timestampRaw) else {
                continue
            }

            guard timestamp >= startDate && timestamp < endDateExclusive else {
                continue
            }

            let info = payload["info"] as? [String: Any]
            let lastUsage = normalizeRawUsage(info?["last_token_usage"])
            let totalUsage = normalizeRawUsage(info?["total_token_usage"])
            var rawUsage = lastUsage

            if rawUsage == nil, let totalUsage {
                rawUsage = subtract(current: totalUsage, previous: previousTotals)
            }

            if let totalUsage {
                previousTotals = totalUsage
            }

            guard let rawUsage else { continue }
            let delta = convertToDelta(rawUsage)
            guard delta.inputTokens > 0 || delta.cachedInputTokens > 0 || delta.outputTokens > 0 else {
                continue
            }

            let model = extractModel(from: payload) ?? extractModel(from: info) ?? currentModel ?? fallbackModel
            currentModel = model
            events.append(CodexTokenUsageEvent(timestamp: timestamp, model: model, delta: delta))
        }

        return events
    }

    private static func normalizeRawUsage(_ value: Any?) -> CodexRawUsage? {
        guard let payload = value as? [String: Any] else { return nil }
        let input = intValue(payload["input_tokens"])
        let cached = intValue(payload["cached_input_tokens"] ?? payload["cache_read_input_tokens"])
        let output = intValue(payload["output_tokens"])
        let reasoning = intValue(payload["reasoning_output_tokens"])
        let reportedTotal = intValue(payload["total_tokens"])

        return CodexRawUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: reportedTotal > 0 ? reportedTotal : input + output
        )
    }

    private static func subtract(current: CodexRawUsage, previous: CodexRawUsage?) -> CodexRawUsage {
        CodexRawUsage(
            inputTokens: max(current.inputTokens - (previous?.inputTokens ?? 0), 0),
            cachedInputTokens: max(current.cachedInputTokens - (previous?.cachedInputTokens ?? 0), 0),
            outputTokens: max(current.outputTokens - (previous?.outputTokens ?? 0), 0),
            reasoningOutputTokens: max(current.reasoningOutputTokens - (previous?.reasoningOutputTokens ?? 0), 0),
            totalTokens: max(current.totalTokens - (previous?.totalTokens ?? 0), 0)
        )
    }

    private static func convertToDelta(_ raw: CodexRawUsage) -> CodexTokenUsageDelta {
        let cachedInputTokens = min(raw.cachedInputTokens, raw.inputTokens)
        return CodexTokenUsageDelta(
            inputTokens: raw.inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: raw.outputTokens,
            reasoningOutputTokens: raw.reasoningOutputTokens,
            totalTokens: raw.totalTokens > 0 ? raw.totalTokens : raw.inputTokens + raw.outputTokens
        )
    }

    private static func extractModel(from value: Any?) -> String? {
        guard let payload = value as? [String: Any] else { return nil }

        for key in ["model", "model_name"] {
            if let model = nonEmptyString(payload[key]) {
                return model
            }
        }

        for key in ["info", "metadata", "payload"] {
            if let nested = extractModel(from: payload[key]) {
                return nested
            }
        }

        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        fractionalTimestampFormatter.date(from: value) ?? plainTimestampFormatter.date(from: value)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let intValue = Int(value) { return intValue }
        return 0
    }

    private static func fetchPricingDataset() -> [String: [String: Any]] {
        let semaphore = DispatchSemaphore(value: 0)
        var dataset: [String: [String: Any]] = [:]

        URLSession.shared.dataTask(with: pricingURL) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            for (key, value) in object {
                if let pricing = value as? [String: Any] {
                    dataset[key] = pricing
                }
            }
        }.resume()

        _ = semaphore.wait(timeout: .now() + 10)
        return dataset
    }

    private static func resolvePricing(for model: String, dataset: [String: [String: Any]]) -> CodexModelPricing? {
        if isOpenRouterFreeModel(model) {
            return CodexModelPricing(inputCostPerToken: 0, cachedInputCostPerToken: 0, outputCostPerToken: 0)
        }

        let directKeys = providerPrefixes.map { "\($0)\(model)" }
        for key in directKeys {
            if let pricing = pricing(from: dataset[key]) {
                return pricing
            }
        }

        if let alias = modelAliases[model] {
            let aliasKeys = providerPrefixes.map { "\($0)\(alias)" }
            for key in aliasKeys {
                if let pricing = pricing(from: dataset[key]) {
                    return pricing
                }
            }
        }

        let normalizedModel = model.lowercased()
        for (key, value) in dataset where key.lowercased() == normalizedModel {
            if let pricing = pricing(from: value) {
                return pricing
            }
        }

        for (key, value) in dataset {
            let normalizedKey = key.lowercased()
            if normalizedKey.contains(normalizedModel) || normalizedModel.contains(normalizedKey) {
                if let pricing = pricing(from: value) {
                    return pricing
                }
            }
        }

        return nil
    }

    private static func pricing(from payload: [String: Any]?) -> CodexModelPricing? {
        guard let payload else { return nil }
        let input = doubleValue(payload["input_cost_per_token"])
        let output = doubleValue(payload["output_cost_per_token"])
        let cached = payload["cache_read_input_token_cost"].map(doubleValue) ?? input
        return CodexModelPricing(
            inputCostPerToken: input,
            cachedInputCostPerToken: cached,
            outputCostPerToken: output
        )
    }

    private static func calculateCostUSD(usage: CodexModelUsageAccumulator, pricing: CodexModelPricing) -> Double {
        let cachedInput = min(usage.cachedInputTokens, usage.inputTokens)
        let nonCachedInput = max(usage.inputTokens - cachedInput, 0)
        return (Double(nonCachedInput) * pricing.inputCostPerToken)
            + (Double(cachedInput) * pricing.cachedInputCostPerToken)
            + (Double(usage.outputTokens) * pricing.outputCostPerToken)
    }

    private static func isOpenRouterFreeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "openrouter/free"
            || (normalized.hasPrefix("openrouter/") && normalized.hasSuffix(":free"))
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String, let doubleValue = Double(value) { return doubleValue }
        return 0
    }
}
