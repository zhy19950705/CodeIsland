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

    static func loadCurrentMonth(now: Date = Date(), fileManager: FileManager = .default) -> UsageMonthlyStat? {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        guard let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return nil
        }

        var events: [CodexTokenUsageEvent] = []
        let directories = candidateDirectories(now: now, fileManager: fileManager)

        if let ripgrepEvents = loadEventsWithRipgrep(
            directories: directories,
            startOfMonth: startOfMonth,
            startOfNextMonth: startOfNextMonth
        ) {
            events = ripgrepEvents
        } else {
            let currentMonthComponent = String(format: "%02d", calendar.component(.month, from: now))
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
                    if directory.lastPathComponent != currentMonthComponent,
                       let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                       let modifiedAt = values.contentModificationDate,
                       modifiedAt < startOfMonth {
                        continue
                    }

                    events.append(
                        contentsOf: loadEvents(
                            from: fileURL,
                            startOfMonth: startOfMonth,
                            startOfNextMonth: startOfNextMonth
                        )
                    )
                }
            }
        }

        guard !events.isEmpty else { return nil }

        var totalTokens = 0
        var models: [String: CodexModelUsageAccumulator] = [:]
        for event in events {
            totalTokens += event.delta.totalTokens
            var usage = models[event.model, default: CodexModelUsageAccumulator()]
            usage.add(event.delta)
            models[event.model] = usage
        }

        let pricingDataset = fetchPricingDataset()
        var totalCostUSD = 0.0
        var hasCost = false
        for (model, usage) in models {
            guard let pricing = resolvePricing(for: model, dataset: pricingDataset) else { continue }
            hasCost = true
            totalCostUSD += calculateCostUSD(usage: usage, pricing: pricing)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yyyyMM")

        return UsageMonthlyStat(
            label: formatter.string(from: now),
            totalTokens: totalTokens,
            costUSD: hasCost ? totalCostUSD : nil
        )
    }

    private static func sessionsDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func candidateDirectories(now: Date, fileManager: FileManager) -> [URL] {
        let calendar = Calendar.current
        let sessionsDirectory = sessionsDirectoryURL(fileManager: fileManager)
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        let previousDate = calendar.date(byAdding: .month, value: -1, to: now)
        let previousComponents = previousDate.map { calendar.dateComponents([.year, .month], from: $0) }

        var directories: [URL] = []
        for components in [currentComponents, previousComponents].compactMap({ $0 }) {
            let year = String(format: "%04d", components.year ?? 0)
            let month = String(format: "%02d", components.month ?? 0)
            directories.append(
                sessionsDirectory
                    .appendingPathComponent(year, isDirectory: true)
                    .appendingPathComponent(month, isDirectory: true)
            )
        }
        return directories
    }

    private static func loadEventsWithRipgrep(
        directories: [URL],
        startOfMonth: Date,
        startOfNextMonth: Date
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
                    startOfMonth: startOfMonth,
                    startOfNextMonth: startOfNextMonth
                )
            )
        }
        return events
    }

    private static func loadEvents(from fileURL: URL, startOfMonth: Date, startOfNextMonth: Date) -> [CodexTokenUsageEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return loadEvents(
            fromMatchedLines: content.split(whereSeparator: \.isNewline).map(String.init),
            fileURL: fileURL,
            startOfMonth: startOfMonth,
            startOfNextMonth: startOfNextMonth
        )
    }

    private static func loadEvents(
        fromMatchedLines lines: [String],
        fileURL: URL,
        startOfMonth: Date,
        startOfNextMonth: Date
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

            guard timestamp >= startOfMonth && timestamp < startOfNextMonth else {
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
