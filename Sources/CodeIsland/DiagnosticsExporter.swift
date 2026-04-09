import AppKit
import Foundation
import CodeIslandCore
import UniformTypeIdentifiers

struct DiagnosticsExportResult: Sendable {
    let archiveURL: URL
    let warnings: [String]
}

struct AppDiagnosticsSnapshot: Codable, Sendable {
    struct SessionRecord: Codable, Sendable {
        let sessionId: String
        let source: String
        let status: String
        let cwd: String?
        let model: String?
        let currentTool: String?
        let termApp: String?
        let termBundleId: String?
        let cliPid: Int32?
        let lastActivity: Date
        let startTime: Date
        let interrupted: Bool
        let isHistoricalSnapshot: Bool
    }

    let exportedAt: Date
    let activeSessionId: String?
    let surface: String
    let permissionQueueCount: Int
    let questionQueueCount: Int
    let sessions: [SessionRecord]
}

actor DiagnosticsExporter {
    static let shared = DiagnosticsExporter()

    private let fileManager = FileManager.default

    private init() {}

    func exportArchive(
        snapshot: AppDiagnosticsSnapshot,
        to destinationURL: URL
    ) async throws -> DiagnosticsExportResult {
        let timestamp = Self.archiveTimestamp()
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodeIsland-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        let exportRoot = tempRoot.appendingPathComponent("CodeIsland-Diagnostics-\(timestamp)", isDirectory: true)
        var warnings: [String] = []

        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        do {
            try writeJSON(snapshot, to: exportRoot.appendingPathComponent("state/live-state.json"))
        } catch {
            warnings.append("Failed to write live state: \(error.localizedDescription)")
        }

        do {
            try await writeMetadata(to: exportRoot.appendingPathComponent("metadata.json"))
        } catch {
            warnings.append("Failed to write metadata: \(error.localizedDescription)")
        }

        let copiedFiles: [(source: URL, relativePath: String)] = [
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codeisland/sessions.json"), "state/sessions.json"),
            (UsageSnapshotStore.cacheURL(fileManager: fileManager), "state/usage_snapshot.json"),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), "configs/claude-settings.json"),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json"), "configs/codex-hooks.json"),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml"), "configs/codex-config.toml"),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/config.json"), "configs/opencode-config.json"),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/plugins/codeisland.js"), "configs/opencode-plugin.js"),
        ]

        for item in copiedFiles {
            do {
                try copyItemIfPresent(from: item.source, toRelativePath: item.relativePath, under: exportRoot)
            } catch {
                warnings.append("Failed to copy \(item.source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        do {
            try await writeUnifiedLogs(to: exportRoot.appendingPathComponent("logs/unified.log"))
        } catch {
            warnings.append("Failed to export unified logs: \(error.localizedDescription)")
        }

        do {
            try await writeCommandOutput(
                executable: "/usr/bin/sw_vers",
                arguments: [],
                to: exportRoot.appendingPathComponent("logs/sw_vers.txt")
            )
        } catch {
            warnings.append("Failed to export sw_vers: \(error.localizedDescription)")
        }

        do {
            try await writeCommandOutput(
                executable: "/usr/bin/defaults",
                arguments: ["read", Bundle.main.bundleIdentifier ?? "com.codeisland"],
                to: exportRoot.appendingPathComponent("logs/defaults.txt")
            )
        } catch {
            warnings.append("Failed to export defaults: \(error.localizedDescription)")
        }

        let archiveURL = destinationURL.pathExtension.lowercased() == "zip"
            ? destinationURL
            : destinationURL.appendingPathExtension("zip")

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        _ = try await runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", exportRoot.path, archiveURL.path]
        )

        try? fileManager.removeItem(at: tempRoot)
        return DiagnosticsExportResult(archiveURL: archiveURL, warnings: warnings)
    }

    private func writeMetadata(to destinationURL: URL) async throws {
        let payload: [String: String] = await MainActor.run {
            [
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppVersion.fallback,
                "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "locale": Locale.current.identifier,
                "timeZone": TimeZone.current.identifier,
            ]
        }

        try writeJSON(payload, to: destinationURL)
    }

    private func writeUnifiedLogs(to destinationURL: URL) async throws {
        try await writeCommandOutput(
            executable: "/usr/bin/log",
            arguments: ["show", "--last", "6h", "--predicate", "subsystem == \"com.codeisland\""],
            to: destinationURL
        )
    }

    private func writeCommandOutput(
        executable: String,
        arguments: [String],
        to destinationURL: URL
    ) async throws {
        let output = try await runCommand(executable: executable, arguments: arguments)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private func runCommand(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "CodeIslandDiagnostics",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: error.isEmpty ? output : error]
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func copyItemIfPresent(from sourceURL: URL, toRelativePath relativePath: String, under rootURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let destinationURL = rootURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
