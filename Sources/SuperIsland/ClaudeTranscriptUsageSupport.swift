import Foundation
import SuperIslandCore

// Claude transcript parsing stays in one helper so the monitor loop can stay small and testable.
struct ClaudeTranscriptUsageSnapshot: Equatable {
    let transcriptPath: String
    let contextTokens: Int
    let outputTokens: Int
    let contextWindowSize: Int
}

// Pure helpers for resolving Claude transcript files and reading recent usage from JSONL tails.
enum ClaudeTranscriptUsageSupport {
    private static let transcriptTailBytes: UInt64 = 50_000

    // Resolve the transcript path from the known project cwd first, then fall back to a lightweight scan.
    static func resolveTranscriptPath(
        sessionId: String,
        cwd: String?,
        cachedPath: String?,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> String? {
        if let cachedPath, fileManager.fileExists(atPath: cachedPath) {
            return cachedPath
        }

        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        if let cwd {
            for root in transcriptRoots(fileManager: fileManager, homeDirectory: homeDirectory) {
                let candidate = root
                    .appendingPathComponent(cwd.claudeProjectDirEncoded(), isDirectory: true)
                    .appendingPathComponent("\(sessionId).jsonl", isDirectory: false)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }

        for root in transcriptRoots(fileManager: fileManager, homeDirectory: homeDirectory) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent == "\(sessionId).jsonl" else { continue }
                return fileURL.path
            }
        }

        return nil
    }

    // Read the newest assistant usage block from the transcript tail instead of loading the whole file.
    static func readUsageSnapshot(
        transcriptPath: String,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> ClaudeTranscriptUsageSnapshot? {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, transcriptTailBytes)
        handle.seek(toFileOffset: fileSize - readSize)

        guard let text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = payload["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }

            let inputTokens = intValue(usage["input_tokens"] ?? usage["prompt_tokens"])
            let cacheCreationTokens = intValue(usage["cache_creation_input_tokens"])
            let cacheReadTokens = intValue(usage["cache_read_input_tokens"] ?? usage["cached_tokens"])
            let outputTokens = intValue(usage["output_tokens"])
            let contextTokens = inputTokens + cacheCreationTokens + cacheReadTokens

            guard contextTokens > 0 || outputTokens > 0 else { continue }

            return ClaudeTranscriptUsageSnapshot(
                transcriptPath: transcriptPath,
                contextTokens: contextTokens,
                outputTokens: outputTokens,
                contextWindowSize: detectContextWindowSize(
                    fileManager: fileManager,
                    homeDirectory: homeDirectory
                )
            )
        }

        return nil
    }

    // Claude defaults to 200k context unless the settings file explicitly opts into a 1m model suffix.
    static func detectContextWindowSize(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> Int {
        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let settingsPaths = [
            homeDirectory.appendingPathComponent(".claude/settings.json", isDirectory: false),
            homeDirectory.appendingPathComponent(".config/claude/settings.json", isDirectory: false),
        ]

        for settingsURL in settingsPaths where fileManager.fileExists(atPath: settingsURL.path) {
            guard let data = try? Data(contentsOf: settingsURL),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if hasMillionTokenMarker(payload["model"]) {
                return 1_000_000
            }

            if let env = payload["env"] as? [String: Any],
               env.values.contains(where: hasMillionTokenMarker) {
                return 1_000_000
            }
        }

        return 200_000
    }

    // The monitor shares the same root set as the monthly usage collector for compatibility.
    private static func transcriptRoots(fileManager: FileManager, homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true),
            homeDirectory.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ]
        .filter { fileManager.fileExists(atPath: $0.path) }
    }

    // Support both string and bridged number values from JSON payloads.
    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, let value = Int(string) { return value }
        return 0
    }

    // Claude encodes the 1m window in model strings like "...[1m]".
    private static func hasMillionTokenMarker(_ raw: Any?) -> Bool {
        guard let string = raw as? String else { return false }
        return string.contains("[1m]")
    }
}
