import Foundation
import Darwin
import SuperIslandCore

enum ClaudeSessionDiscovery {
    static func findActiveSessions() -> [DiscoveredSession] {
        let claudePids = findPIDs()
        guard !claudePids.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        var results: [DiscoveredSession] = []
        var seenSessionIds: Set<String> = []

        for pid in claudePids {
            guard let cwd = SessionProcessInspector.cwd(for: pid), !cwd.isEmpty else { continue }

            if SessionFilter.isSyntheticAgentWorktree(cwd) {
                continue
            }

            if SessionFilter.shouldIgnoreSession(source: "claude", cwd: cwd, termBundleId: nil) {
                continue
            }

            let processStart = SessionProcessInspector.processStartTime(for: pid)
            let projectPath = "\(home)/.claude/projects/\(cwd.claudeProjectDirEncoded())"
            guard let files = SessionProcessInspector.directoryContents(atPath: projectPath, fileManager: fileManager) else {
                continue
            }

            var bestFile: String?
            var bestDate = Date.distantPast
            for file in files where file.hasSuffix(".jsonl") {
                let fullPath = "\(projectPath)/\(file)"
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified > bestDate {
                    if let processStart, modified < processStart.addingTimeInterval(-10) {
                        continue
                    }
                    bestDate = modified
                    bestFile = file
                }
            }

            guard let file = bestFile else { continue }
            if bestDate.timeIntervalSinceNow < -300 { continue }

            let sessionId = String(file.dropLast(6))
            guard seenSessionIds.insert(sessionId).inserted else { continue }

            let (model, messages) = readRecentTranscript(path: "\(projectPath)/\(file)")
            results.append(
                DiscoveredSession(
                    sessionId: sessionId,
                    cwd: cwd,
                    tty: nil,
                    model: model,
                    pid: pid,
                    modifiedAt: bestDate,
                    recentMessages: messages
                )
            )
        }

        return results
    }

    static func findPIDs() -> [pid_t] {
        let claudeVersionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions").path
        return SessionProcessInspector.findPIDs(cacheKey: "claude") { _, path in
            path.hasPrefix(claudeVersionsDir)
        }
    }

    private static func readRecentTranscript(path: String) -> (String?, [ChatMessage]) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, []) }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, []) }

        var model: String?
        var userMessages: [(Int, String)] = []
        var assistantMessages: [(Int, String)] = []
        var index = 0

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String else { continue }

            if model == nil, let value = message["model"] as? String, !value.isEmpty {
                model = value
            }

            let textContent: String?
            if let content = message["content"] as? String, !content.isEmpty {
                textContent = content
            } else if let contentArray = message["content"] as? [[String: Any]] {
                textContent = contentArray.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            } else {
                textContent = nil
            }

            if let textContent {
                if role == "user" {
                    userMessages.append((index, textContent))
                } else if role == "assistant" {
                    assistantMessages.append((index, textContent))
                }
            }
            index += 1
        }

        var combined: [(Int, ChatMessage)] = []
        userMessages.suffix(3).forEach { combined.append(($0.0, ChatMessage(isUser: true, text: $0.1))) }
        assistantMessages.suffix(3).forEach { combined.append(($0.0, ChatMessage(isUser: false, text: $0.1))) }
        combined.sort { $0.0 < $1.0 }
        return (model, Array(combined.suffix(3).map(\.1)))
    }
}
