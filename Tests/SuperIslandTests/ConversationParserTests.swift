import XCTest
import SuperIslandCore
@testable import SuperIsland

final class ConversationParserTests: XCTestCase {
    // Claude transcripts should keep tool rows structured so the panel can show file previews instead of raw JSON.
    func testClaudeTranscriptParsesStructuredReadResult() async throws {
        let parser = ConversationParser()
        let rootURL = makeTemporaryDirectory()
        let transcriptURL = rootURL.appendingPathComponent("claude.jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "timestamp": "2026-04-15T12:00:00.000Z",
                    "message": [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": "Read Sources/App.swift"]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:01.000Z",
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "thinking", "thinking": "Inspecting the file contents."],
                            [
                                "type": "tool_use",
                                "id": "toolu_1",
                                "name": "Read",
                                "input": ["file_path": "/tmp/App.swift"]
                            ]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:02.000Z",
                    "toolName": "Read",
                    "toolUseResult": [
                        "file": [
                            "filePath": "/tmp/App.swift",
                            "content": "line 3\nline 4",
                            "startLine": 3,
                            "totalLines": 20
                        ]
                    ],
                    "message": [
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_1",
                                "content": "ok",
                                "is_error": false
                            ]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:03.000Z",
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "text", "text": "Done."]
                        ]
                    ]
                ]
            ],
            to: transcriptURL
        )

        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/Volumes/work/island/SuperIsland"
        session.claudeTranscriptPath = transcriptURL.path

        let state = await parser.parseHistory(sessionId: "claude-test", session: session)

        XCTAssertEqual(state.items.count, 4)
        XCTAssertEqual(state.sourcePath, transcriptURL.path)

        guard case .toolCall(let tool) = state.items[2].kind else {
            return XCTFail("Expected a tool-call row in the Claude transcript")
        }
        XCTAssertEqual(tool.name, "Read")
        XCTAssertEqual(tool.status, .success)

        guard case .read(let result)? = tool.structuredResult else {
            return XCTFail("Expected a structured read result")
        }
        XCTAssertEqual(result.filePath, "/tmp/App.swift")
        XCTAssertEqual(result.startLine, 3)
        XCTAssertEqual(result.totalLines, 20)
        XCTAssertEqual(result.content, "line 3\nline 4")
    }

    // Claude `/clear` should reset the visible detail history so stale pre-clear turns
    // do not keep inflating the same session's transcript panel.
    func testClaudeTranscriptDropsHistoryBeforeClearCommand() async throws {
        let parser = ConversationParser()
        let rootURL = makeTemporaryDirectory()
        let transcriptURL = rootURL.appendingPathComponent("claude-clear.jsonl", isDirectory: false)

        try writeJSONLines(
            [
                [
                    "timestamp": "2026-04-15T12:00:00.000Z",
                    "message": [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": "old prompt"]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:01.000Z",
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "text", "text": "old answer"]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:02.000Z",
                    "message": [
                        "role": "user",
                        "content": "<command-name>/clear</command-name>"
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:03.000Z",
                    "message": [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": "new prompt"]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-04-15T12:00:04.000Z",
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "text", "text": "new answer"]
                        ]
                    ]
                ]
            ],
            to: transcriptURL
        )

        var session = SessionSnapshot()
        session.source = "claude"
        session.cwd = "/Volumes/work/island/SuperIsland"
        session.claudeTranscriptPath = transcriptURL.path

        let state = await parser.parseHistory(sessionId: "claude-clear-test", session: session)

        XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.items[0].kind, .user("new prompt"))
        XCTAssertEqual(state.items[1].kind, .assistant("new answer"))
    }

    // Codex rollout parsing should decode JSON tool outputs so Bash results render with the specialized command view.
    func testCodexRolloutParsesStructuredBashResultFromJSONOutput() async throws {
        let parser = ConversationParser()
        let sessionsRoot = makeTemporaryDirectory()
            .appendingPathComponent("sessions", isDirectory: true)
        let rolloutURL = try makeCodexRolloutURL(in: sessionsRoot)
        let outputJSON = #"{"stdout":"build ok","stderr":"","interrupted":false,"returnCodeInterpretation":"exit 0"}"#

        try writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "payload": [
                        "id": "thread-123",
                        "cwd": "/Volumes/work/island/SuperIsland"
                    ]
                ],
                [
                    "timestamp": 1_713_182_400.0,
                    "type": "event_msg",
                    "payload": [
                        "type": "user_message",
                        "message": "Run tests"
                    ]
                ],
                [
                    "timestamp": 1_713_182_401.0,
                    "type": "response_item",
                    "payload": [
                        "type": "function_call",
                        "call_id": "call_1",
                        "name": "exec_command",
                        "arguments": #"{"cmd":"swift test"}"#
                    ]
                ],
                [
                    "timestamp": 1_713_182_402.0,
                    "type": "response_item",
                    "payload": [
                        "type": "function_call_output",
                        "call_id": "call_1",
                        "output": outputJSON
                    ]
                ],
                [
                    "timestamp": 1_713_182_403.0,
                    "type": "response_item",
                    "payload": [
                        "type": "message",
                        "role": "assistant",
                        "content": [
                            ["type": "output_text", "text": "Tests finished."]
                        ]
                    ]
                ]
            ],
            to: rolloutURL
        )

        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/Volumes/work/island/SuperIsland"
        session.providerSessionId = "thread-123"

        let state = await parser.parseCodexConversation(
            sessionId: "tracked-session",
            session: session,
            sessionsBasePath: sessionsRoot.path
        )

        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.sourcePath, rolloutURL.path)

        guard case .toolCall(let tool) = state.items[1].kind else {
            return XCTFail("Expected a tool-call row in the Codex rollout")
        }
        XCTAssertEqual(tool.name, "Bash")
        XCTAssertEqual(tool.status, .success)
        XCTAssertEqual(tool.input["cmd"], "swift test")

        guard case .bash(let result)? = tool.structuredResult else {
            return XCTFail("Expected a structured bash result")
        }
        XCTAssertEqual(result.stdout, "build ok")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.interrupted, false)
        XCTAssertEqual(result.returnCodeInterpretation, "exit 0")
    }

    // Long Codex rollouts should preserve early chat turns instead of truncating to the last tail chunk only.
    func testCodexRolloutParsesFullHistoryInsteadOfTailOnly() async throws {
        let parser = ConversationParser()
        let sessionsRoot = makeTemporaryDirectory()
            .appendingPathComponent("sessions", isDirectory: true)
        let rolloutURL = try makeCodexRolloutURL(in: sessionsRoot)

        var objects: [[String: Any]] = [
            [
                "type": "session_meta",
                "payload": [
                    "id": "thread-long",
                    "cwd": "/Volumes/work/island/SuperIsland"
                ]
            ],
            [
                "timestamp": 1_713_182_300.0,
                "type": "event_msg",
                "payload": [
                    "type": "user_message",
                    "message": "top-of-file prompt"
                ]
            ]
        ]

        let fillerText = String(repeating: "filler-content-", count: 18)
        for index in 0..<2_400 {
            objects.append(
                [
                    "timestamp": 1_713_182_301.0 + Double(index),
                    "type": "event_msg",
                    "payload": [
                        "type": "agent_message",
                        "message": "\(index)-\(fillerText)"
                    ]
                ]
            )
        }

        objects.append(
            [
                "timestamp": 1_713_184_800.0,
                "type": "response_item",
                "payload": [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "tail-of-file reply"]
                    ]
                ]
            ]
        )

        try writeJSONLines(objects, to: rolloutURL)

        var session = SessionSnapshot()
        session.source = "codex"
        session.cwd = "/Volumes/work/island/SuperIsland"
        session.providerSessionId = "thread-long"

        let state = await parser.parseCodexConversation(
            sessionId: "tracked-long-session",
            session: session,
            sessionsBasePath: sessionsRoot.path
        )

        XCTAssertEqual(state.sourcePath, rolloutURL.path)
        XCTAssertEqual(state.items.first?.kind, .user("top-of-file prompt"))
        XCTAssertEqual(state.items.last?.kind, .assistant("tail-of-file reply"))
        XCTAssertEqual(state.items.count, 2_402)
    }

    // Each test uses a unique directory so transcript fixtures never collide with the developer's real data.
    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    // Match Codex's YYYY/MM/DD session layout so the parser scans the temp fixtures exactly like the real client data.
    private func makeCodexRolloutURL(in sessionsRoot: URL) throws -> URL {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let directoryURL = sessionsRoot
            .appendingPathComponent(String(format: "%04d", components.year ?? 2000), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", components.month ?? 1), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", components.day ?? 1), isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("rollout.jsonl", isDirectory: false)
    }

    // Serializing fixture dictionaries keeps the JSONL samples readable while guaranteeing valid escaping.
    private func writeJSONLines(_ objects: [[String: Any]], to url: URL) throws {
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let string = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "ConversationParserTests", code: 1)
            }
            return string
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
