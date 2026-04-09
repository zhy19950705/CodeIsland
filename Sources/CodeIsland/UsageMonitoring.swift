import Foundation
import AppKit
#if canImport(Darwin)
import Darwin
#endif

enum UsageProviderSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var sortOrder: Int {
        switch self {
        case .claude: 0
        case .codex: 1
        }
    }
}

struct UsageWindowStat: Codable, Hashable, Sendable {
    var label: String
    var percentage: Int
    var detail: String
    var tintHex: String
}

struct UsageMonthlyStat: Codable, Hashable, Sendable {
    var label: String
    var totalTokens: Int
    var costUSD: Double?
}

struct UsageProviderSnapshot: Codable, Hashable, Sendable, Identifiable {
    var source: UsageProviderSource
    var primary: UsageWindowStat
    var secondary: UsageWindowStat
    var updatedAtUnix: TimeInterval?
    var summary: String?
    var monthly: UsageMonthlyStat?

    var id: String { source.rawValue }
}

struct UsageSnapshot: Codable, Hashable, Sendable {
    var providers: [UsageProviderSnapshot]

    static let empty = UsageSnapshot(providers: [])
}

struct UsageUpdateEnvelope: Codable, Sendable {
    let type: String
    let usage: UsageSnapshot

    init(usage: UsageSnapshot) {
        self.type = "usage_update"
        self.usage = usage
    }
}

enum UsageSnapshotStore {
    private static let notificationName = Notification.Name("CodeIslandUsageSnapshotDidUpdate")

    static var didUpdateNotification: Notification.Name { notificationName }

    static func cacheURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeisland", isDirectory: true)
            .appendingPathComponent("usage_snapshot.json", isDirectory: false)
    }

    static func load(fileManager: FileManager = .default) -> UsageSnapshot {
        let url = cacheURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    @discardableResult
    static func save(_ snapshot: UsageSnapshot, fileManager: FileManager = .default) -> Bool {
        let url = cacheURL(fileManager: fileManager)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: notificationName, object: nil)
            return true
        } catch {
            return false
        }
    }
}

enum UsageMonitorLaunchAgentState: String, Sendable {
    case enabled
    case disabled
    case unavailable

    var title: String {
        switch self {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .unavailable: "Unavailable"
        }
    }
}

struct UsageMonitorLaunchAgentSnapshot: Sendable {
    var state: UsageMonitorLaunchAgentState
    var detail: String
    var plistPath: String
    var needsRepair: Bool = false
}

enum UsageMonitorLaunchAgentError: LocalizedError {
    case executableMissing
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "Missing executable"
        case let .launchctlFailed(message):
            message
        }
    }
}

final class UsageMonitorLaunchAgentManager {
    private let fileManager: FileManager
    private let label = "com.codeisland.usage-monitor"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> UsageMonitorLaunchAgentSnapshot {
        let plistURL = launchAgentPlistURL()
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            return UsageMonitorLaunchAgentSnapshot(
                state: .unavailable,
                detail: "CodeIsland executable is unavailable",
                plistPath: plistURL.path
            )
        }

        if let installedExecutablePath = installedExecutablePath(plistURL: plistURL),
           installedExecutablePath != executableURL.path {
            return UsageMonitorLaunchAgentSnapshot(
                state: .disabled,
                detail: "Installed for an older build path; re-enable to repair",
                plistPath: plistURL.path,
                needsRepair: true
            )
        }

        if let service = serviceStatus() {
            if service.jobState == "spawn failed" {
                let detail = service.lastExitCode.map { "Monitor failed to start (exit \($0)); re-enable to repair" }
                    ?? "Monitor failed to start; re-enable to repair"
                return UsageMonitorLaunchAgentSnapshot(
                    state: .disabled,
                    detail: detail,
                    plistPath: plistURL.path,
                    needsRepair: true
                )
            }

            if service.isLoaded {
                return UsageMonitorLaunchAgentSnapshot(
                    state: .enabled,
                    detail: "Collects Claude/Codex usage every 15 minutes",
                    plistPath: plistURL.path
                )
            }
        }

        if isLoaded() {
            return UsageMonitorLaunchAgentSnapshot(
                state: .enabled,
                detail: "Collects Claude/Codex usage every 15 minutes",
                plistPath: plistURL.path
            )
        }

        let detail = fileManager.fileExists(atPath: plistURL.path)
            ? "Installed but not loaded"
            : "LaunchAgent not installed"
        return UsageMonitorLaunchAgentSnapshot(state: .disabled, detail: detail, plistPath: plistURL.path)
    }

    @discardableResult
    func repairIfNeeded() throws -> Bool {
        let current = snapshot()
        guard current.needsRepair else { return false }
        try setEnabled(true)
        return true
    }

    func setEnabled(_ enabled: Bool) throws {
        let plistURL = launchAgentPlistURL()
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            throw UsageMonitorLaunchAgentError.executableMissing
        }

        if enabled {
            try writePlist(at: plistURL, executableURL: executableURL)
            bootoutIfPresent(plistURL: plistURL)
            try runLaunchctl(["bootstrap", launchDomain(), plistURL.path])
            try runLaunchctl(["enable", "\(launchDomain())/\(label)"])
            try runLaunchctl(["kickstart", "-k", "\(launchDomain())/\(label)"])
        } else {
            _ = try? runLaunchctl(["disable", "\(launchDomain())/\(label)"])
            bootoutIfPresent(plistURL: plistURL)
            waitForServiceRemoval()
            if fileManager.fileExists(atPath: plistURL.path) {
                try fileManager.removeItem(at: plistURL)
            }
        }
    }

    func runNow() throws {
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            throw UsageMonitorLaunchAgentError.executableMissing
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--monitor-usage", "--once"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = (process.standardError as? Pipe).flatMap {
                String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw UsageMonitorLaunchAgentError.launchctlFailed(stderr.isEmpty ? "Usage refresh failed" : stderr)
        }
    }

    private func launchAgentPlistURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private func launchDomain() -> String {
        "gui/\(getuid())"
    }

    private func isLoaded() -> Bool {
        (try? runLaunchctl(["print", "\(launchDomain())/\(label)"])) != nil
    }

    private func installedExecutablePath(plistURL: URL) -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let executablePath = arguments.first,
              !executablePath.isEmpty else {
            return nil
        }
        return executablePath
    }

    private func serviceStatus() -> LaunchServiceStatus? {
        guard let output = try? runLaunchctl(["print", "\(launchDomain())/\(label)"]) else {
            return nil
        }
        return LaunchServiceStatus(output: output)
    }

    private func bootoutIfPresent(plistURL: URL) {
        _ = try? runLaunchctl(["bootout", launchDomain(), label])
        _ = try? runLaunchctl(["bootout", launchDomain(), plistURL.path])
    }

    private func waitForServiceRemoval() {
        for _ in 0..<20 {
            guard isLoaded() else { return }
            usleep(100_000)
        }
    }

    private func writePlist(at plistURL: URL, executableURL: URL) throws {
        let logsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeisland", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                executableURL.path,
                "--monitor-usage",
                "--once",
            ],
            "WorkingDirectory": fileManager.homeDirectoryForCurrentUser.path,
            "RunAtLoad": true,
            "StartInterval": 900,
            "StandardOutPath": logsDirectory.appendingPathComponent("usage-monitor.log").path,
            "StandardErrorPath": logsDirectory.appendingPathComponent("usage-monitor.error.log").path,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw UsageMonitorLaunchAgentError.launchctlFailed(output.isEmpty ? "launchctl failed" : output)
        }
        return output
    }
}

private struct LaunchServiceStatus {
    let output: String

    var isLoaded: Bool {
        output.contains("state =")
    }

    var jobState: String? {
        extractValue(after: "job state = ")
    }

    var lastExitCode: Int? {
        guard let raw = extractValue(after: "last exit code = ") else { return nil }
        let code = raw.split(separator: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        return Int(code)
    }

    private func extractValue(after prefix: String) -> String? {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else { return nil }
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }
}
