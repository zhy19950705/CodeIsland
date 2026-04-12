import XCTest
@testable import CodeIsland

final class CodexMonthlyUsageCalculatorTests: XCTestCase {
    func testLoadUsageHistoryFiltersToRecentThirtyDays() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-04-10T12:00:00Z"))

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirectory = tempDirectory.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        try writeSessionFile(
            sessionsDirectory: sessionsDirectory,
            year: "2026",
            month: "04",
            name: "recent.jsonl",
            lines: [
                try makeJSONLine([
                    "timestamp": "2026-04-08T09:00:00Z",
                    "type": "turn_context",
                    "payload": ["model": "gpt-5"],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-04-08T09:00:01Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "token_count",
                        "model": "gpt-5",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 1_000,
                                "cached_input_tokens": 0,
                                "output_tokens": 400,
                                "total_tokens": 1_400,
                            ],
                        ],
                    ],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-04-08T10:00:00Z",
                    "type": "turn_context",
                    "payload": ["model": "gpt-5-mini"],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-04-08T10:00:01Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "token_count",
                        "model": "gpt-5-mini",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 500,
                                "cached_input_tokens": 0,
                                "output_tokens": 100,
                                "total_tokens": 600,
                            ],
                        ],
                    ],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-04-01T12:00:00Z",
                    "type": "turn_context",
                    "payload": ["model": "gpt-5"],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-04-01T12:00:01Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "token_count",
                        "model": "gpt-5",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 300,
                                "cached_input_tokens": 0,
                                "output_tokens": 100,
                                "total_tokens": 400,
                            ],
                        ],
                    ],
                ]),
            ]
        )

        try writeSessionFile(
            sessionsDirectory: sessionsDirectory,
            year: "2026",
            month: "03",
            name: "march.jsonl",
            lines: [
                try makeJSONLine([
                    "timestamp": "2026-03-20T09:00:00Z",
                    "type": "turn_context",
                    "payload": ["model": "gpt-5"],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-03-20T09:00:01Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "token_count",
                        "model": "gpt-5",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 200,
                                "cached_input_tokens": 0,
                                "output_tokens": 50,
                                "total_tokens": 250,
                            ],
                        ],
                    ],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-03-01T09:00:00Z",
                    "type": "turn_context",
                    "payload": ["model": "gpt-5"],
                ]),
                try makeJSONLine([
                    "timestamp": "2026-03-01T09:00:01Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "token_count",
                        "model": "gpt-5",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 900,
                                "cached_input_tokens": 0,
                                "output_tokens": 100,
                                "total_tokens": 1_000,
                            ],
                        ],
                    ],
                ]),
            ]
        )

        let result = CodexMonthlyUsageCalculator.loadUsageHistory(
            now: now,
            sessionsDirectory: sessionsDirectory,
            pricingDataset: pricingDataset()
        )

        XCTAssertEqual(result.history.count, 3)

        let weekHistory = try XCTUnwrap(result.history.first(where: { $0.preset == .thisWeek }))
        XCTAssertEqual(weekHistory.totalTokens, 2_000)
        XCTAssertEqual(weekHistory.rows.count, 2)
        XCTAssertEqual(weekHistory.rows.map(\.totalTokens), [1_400, 600])

        let monthHistory = try XCTUnwrap(result.history.first(where: { $0.preset == .thisMonth }))
        XCTAssertEqual(monthHistory.totalTokens, 2_400)
        XCTAssertEqual(monthHistory.rows.count, 3)
        XCTAssertEqual(monthHistory.rows.map(\.totalTokens), [1_400, 600, 400])

        let recentHistory = try XCTUnwrap(result.history.first(where: { $0.preset == .recent30Days }))
        XCTAssertEqual(recentHistory.preset, .recent30Days)
        XCTAssertEqual(recentHistory.totalTokens, 2_650)
        XCTAssertEqual(recentHistory.rows.count, 4)
        XCTAssertEqual(recentHistory.rows.map(\.totalTokens), [1_400, 600, 400, 250])
        XCTAssertEqual(recentHistory.costUSD ?? 0, 2.95, accuracy: 0.0001)
        XCTAssertNotNil(recentHistory.label)

        let summary = try XCTUnwrap(result.monthly)
        XCTAssertEqual(summary.totalTokens, 2_650)
        XCTAssertEqual(summary.costUSD ?? 0, 2.95, accuracy: 0.0001)
        XCTAssertTrue(summary.label.contains(" - "))
    }

    private func pricingDataset() -> [String: [String: Any]] {
        [
            "gpt-5": [
                "input_cost_per_token": 0.001,
                "output_cost_per_token": 0.002,
            ],
            "gpt-5-mini": [
                "input_cost_per_token": 0.0005,
                "output_cost_per_token": 0.001,
            ],
        ]
    }

    private func writeSessionFile(
        sessionsDirectory: URL,
        year: String,
        month: String,
        name: String,
        lines: [String]
    ) throws {
        let directory = sessionsDirectory
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(
            to: directory.appendingPathComponent(name, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeJSONLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
