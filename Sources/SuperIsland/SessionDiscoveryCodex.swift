import Foundation
import Darwin
import SuperIslandCore

enum CodexSessionDiscovery {
    static func findActiveSessions() -> [DiscoveredSession] {
        let codexPids = findPIDs()
        guard !codexPids.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        let sessionsBase = "\(home)/.codex/sessions"
        guard fileManager.fileExists(atPath: sessionsBase) else { return [] }

        var results: [DiscoveredSession] = []
        var seenSessionIds: Set<String> = []

        for pid in codexPids {
            guard let cwd = SessionProcessInspector.cwd(for: pid), !cwd.isEmpty else { continue }
            let processStart = SessionProcessInspector.processStartTime(for: pid)

            guard let bestFile = findRecentSession(base: sessionsBase, cwd: cwd, after: processStart, fileManager: fileManager) else {
                continue
            }

            let sessionId = extractSessionId(from: (bestFile as NSString).lastPathComponent)
            guard !sessionId.isEmpty, seenSessionIds.insert(sessionId).inserted else { continue }

            let modifiedAt = (try? fileManager.attributesOfItem(atPath: bestFile))?[.modificationDate] as? Date ?? Date()
            if modifiedAt.timeIntervalSinceNow < -300 { continue }

            let (model, messages) = readRecentTranscript(path: bestFile)
            results.append(
                DiscoveredSession(
                    sessionId: sessionId,
                    cwd: cwd,
                    tty: nil,
                    model: model,
                    pid: pid,
                    modifiedAt: modifiedAt,
                    recentMessages: messages,
                    source: "codex"
                )
            )
        }

        return results
    }

    static func findPIDs() -> [pid_t] {
        SessionProcessInspector.findPIDs(cacheKey: "codex") { pid, path in
            let lowercased = path.lowercased()
            if lowercased.contains("codex.app/contents/") && lowercased.hasSuffix("/codex") {
                return true
            }
            if lowercased.hasSuffix("/node"),
               let args = SessionProcessInspector.processArgs(for: pid) {
                return args.contains(where: { $0.contains("@openai/codex") || $0.contains("openai-codex") })
            }
            return false
        }
    }

    private static func findRecentSession(base: String, cwd: String, after: Date?, fileManager: FileManager) -> String? {
        let calendar = Calendar.current
        let now = Date()
        var directories: [String] = []

        for daysBack in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            let year = String(format: "%04d", calendar.component(.year, from: date))
            let month = String(format: "%02d", calendar.component(.month, from: date))
            let day = String(format: "%02d", calendar.component(.day, from: date))
            let directory = "\(base)/\(year)/\(month)/\(day)"
            if fileManager.fileExists(atPath: directory) {
                directories.append(directory)
            }
        }

        for directory in directories {
            guard let files = SessionProcessInspector.directoryContents(atPath: directory, fileManager: fileManager) else { continue }
            for file in files.filter({ $0.hasSuffix(".jsonl") }).sorted(by: >).prefix(20) {
                let fullPath = "\(directory)/\(file)"
                if let after,
                   let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified < after.addingTimeInterval(-10) {
                    continue
                }
                if sessionMatchesCwd(path: fullPath, cwd: cwd) {
                    return fullPath
                }
            }
        }

        return nil
    }

    private static func sessionMatchesCwd(path: String, cwd: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }

        let data = handle.readData(ofLength: 4096)
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\n").first,
              let lineData = firstLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let sessionCwd = payload["cwd"] as? String else {
            return false
        }
        return sessionCwd == cwd
    }

    private static func extractSessionId(from filename: String) -> String {
        let name = filename.replacingOccurrences(of: ".jsonl", with: "")
        let parts = name.split(separator: "-")
        if parts.count >= 11 {
            return parts.suffix(5).joined(separator: "-")
        }
        return name
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
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""

            if type == "session_meta", model == nil,
               let payload = json["payload"] as? [String: Any] {
                model = payload["model"] as? String ?? payload["model_provider"] as? String
            }

            if type == "event_msg",
               let payload = json["payload"] as? [String: Any],
               let msgType = payload["type"] as? String,
               let message = payload["message"] as? String,
               !message.isEmpty {
                if msgType == "user_message" {
                    userMessages.append((index, message))
                } else if msgType == "agent_message" {
                    assistantMessages.append((index, message))
                }
            }

            if type == "response_item",
               let payload = json["payload"] as? [String: Any],
               let role = payload["role"] as? String,
               let content = payload["content"] as? [[String: Any]] {
                for item in content {
                    let itemType = item["type"] as? String ?? ""
                    guard let text = item["text"] as? String, !text.isEmpty else { continue }
                    if role == "user" && itemType == "input_text" && userMessages.isEmpty {
                        userMessages.append((index, text))
                    } else if role == "assistant" && itemType == "output_text" && assistantMessages.last?.1 != text {
                        assistantMessages.append((index, text))
                    }
                    break
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
