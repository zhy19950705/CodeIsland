import Foundation

@MainActor
final class HookPolicy {
    static let shared = HookPolicy()

    private static let defaultAutoApproveTools: Set<String> = [
        "TaskCreate", "TaskUpdate", "TaskGet", "TaskList", "TaskOutput", "TaskStop",
        "TodoRead", "TodoWrite",
        "EnterPlanMode", "ExitPlanMode",
    ]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    var autoApproveTools: Set<String> {
        guard let configured = defaults.array(forKey: SettingsKey.hookAutoApproveTools) as? [String] else {
            return loadConfiguredToolsFromDisk() ?? Self.defaultAutoApproveTools
        }
        let normalized = configured
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? [] : Set(normalized)
    }

    func shouldAutoApprove(toolName: String?) -> Bool {
        guard let toolName else { return false }
        return autoApproveTools.contains(toolName)
    }

    private func loadConfiguredToolsFromDisk() -> Set<String>? {
        let candidates = [
            homeDirectory
                .appendingPathComponent(".superisland", isDirectory: true)
                .appendingPathComponent("hook-policy.json", isDirectory: false),
            homeDirectory
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("superisland", isDirectory: true)
                .appendingPathComponent("hook-policy.json", isDirectory: false),
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let tools = parseConfiguredTools(from: data) {
                return tools
            }
        }
        return nil
    }

    private func parseConfiguredTools(from data: Data) -> Set<String>? {
        if let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            let normalized = array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Set(normalized)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = object["autoApproveTools"] as? [String] else {
            return nil
        }

        let normalized = array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(normalized)
    }
}
