import Foundation
import AppKit
#if canImport(Darwin)
import Darwin
#endif

enum UsageProviderSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    var sortOrder: Int {
        switch self {
        case .claude: 0
        case .codex: 1
        case .cursor: 2
        }
    }

    var displaysUsedPercentage: Bool {
        switch self {
        case .claude, .cursor:
            true
        case .codex:
            false
        }
    }
}

struct UsageWindowStat: Codable, Hashable, Sendable {
    var label: String
    var percentage: Int
    var detail: String
    // Keep reset timestamps optional so cached snapshots from older builds still decode cleanly.
    var refreshAtUnix: TimeInterval? = nil
    var tintHex: String
}

struct UsageMonthlyStat: Codable, Hashable, Sendable {
    var label: String
    var totalTokens: Int
    var costUSD: Double?
}

enum UsageHistoryRangePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case recent30Days

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .thisWeek: 0
        case .thisMonth: 1
        case .recent30Days: 2
        }
    }
}

struct UsageHistoryRow: Codable, Hashable, Sendable, Identifiable {
    var dayStartUnix: TimeInterval
    var model: String
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var costUSD: Double?

    var id: String { "\(Int(dayStartUnix))::\(model)" }
}

struct UsageHistoryRangeSnapshot: Codable, Hashable, Sendable, Identifiable {
    var preset: UsageHistoryRangePreset
    var label: String?
    var totalTokens: Int
    var costUSD: Double?
    var rows: [UsageHistoryRow]

    var id: String { preset.rawValue }
}

struct UsageProviderSnapshot: Codable, Hashable, Sendable, Identifiable {
    var source: UsageProviderSource
    var primary: UsageWindowStat
    var secondary: UsageWindowStat
    var updatedAtUnix: TimeInterval?
    var summary: String?
    var monthly: UsageMonthlyStat?
    var history: [UsageHistoryRangeSnapshot]?
    var showsQuotaBadge: Bool?

    var id: String { source.rawValue }

    var hasQuotaMetrics: Bool { showsQuotaBadge ?? true }
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
    private static let notificationName = Notification.Name("SuperIslandUsageSnapshotDidUpdate")

    static var didUpdateNotification: Notification.Name { notificationName }

    static func cacheURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".superisland", isDirectory: true)
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
            "缺少可执行文件"
        case let .launchctlFailed(message):
            message
        }
    }
}

final class UsageMonitorLaunchAgentManager {
    private let fileManager: FileManager
    private let label = "com.superisland.usage-monitor"
    private let collectionInterval: TimeInterval = 300

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> UsageMonitorLaunchAgentSnapshot {
        let plistURL = launchAgentPlistURL()
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            return UsageMonitorLaunchAgentSnapshot(
                state: .unavailable,
                detail: "SuperIsland 可执行文件不可用",
                plistPath: plistURL.path
            )
        }

        if let installedExecutablePath = installedExecutablePath(plistURL: plistURL),
           installedExecutablePath != executableURL.path {
            return UsageMonitorLaunchAgentSnapshot(
                state: .disabled,
                detail: "当前安装记录指向旧构建路径，请重新启用以修复",
                plistPath: plistURL.path,
                needsRepair: true
            )
        }

        if let service = serviceStatus() {
            if service.jobState == "spawn failed" {
                let detail = service.lastExitCode.map { "监控进程启动失败（退出码 \($0)），请重新启用以修复" }
                    ?? "监控进程启动失败，请重新启用以修复"
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
                    detail: enabledDetail,
                    plistPath: plistURL.path
                )
            }
        }

        if isLoaded() {
            return UsageMonitorLaunchAgentSnapshot(
                state: .enabled,
                detail: enabledDetail,
                plistPath: plistURL.path
            )
        }

        let detail = fileManager.fileExists(atPath: plistURL.path)
            ? "已安装但未加载"
            : "未安装 LaunchAgent"
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

    func runNow() async throws {
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            throw UsageMonitorLaunchAgentError.executableMissing
        }

        let stderr = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--monitor-usage", "--once"]
        process.standardOutput = Pipe()
        process.standardError = stderr

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else {
                    continuation.resume()
                    return
                }

                let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(throwing: UsageMonitorLaunchAgentError.launchctlFailed(
                    message.isEmpty ? "Usage refresh failed" : message
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
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

    private var enabledDetail: String {
        let minutes = Int(collectionInterval / 60)
        return "Collects Claude/Codex usage every \(minutes) minutes"
    }

    private func writePlist(at plistURL: URL, executableURL: URL) throws {
        let logsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".superisland", isDirectory: true)
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
            "StartInterval": Int(collectionInterval),
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
