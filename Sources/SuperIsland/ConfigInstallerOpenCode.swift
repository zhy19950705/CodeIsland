import Foundation

// OpenCode plugin handling is separated because it touches a different config surface than JSON hook files.
extension ConfigInstaller {
    static func opencodePluginSource() -> String? {
        if let url = AppResourceBundle.bundle.url(forResource: "superisland-opencode", withExtension: "js", subdirectory: "Resources"),
           let source = try? String(contentsOf: url) {
            return source
        }
        if let url = AppResourceBundle.bundle.url(forResource: "superisland-opencode", withExtension: "js"),
           let source = try? String(contentsOf: url) {
            return source
        }
        return nil
    }

    @discardableResult
    static func installOpencodePlugin(fm: FileManager) -> Bool {
        let configDirectory = (opencodeConfigPath as NSString).deletingLastPathComponent
        guard fm.fileExists(atPath: configDirectory) else { return true }

        let oldPlugin = opencodePluginDir + "/vibe-island.js"
        if fm.fileExists(atPath: oldPlugin) {
            try? fm.removeItem(atPath: oldPlugin)
        }

        guard let source = opencodePluginSource() else { return false }
        try? fm.createDirectory(atPath: opencodePluginDir, withIntermediateDirectories: true)
        guard fm.createFile(atPath: opencodePluginPath, contents: Data(source.utf8)) else { return false }

        let pluginReference = "file://\(opencodePluginPath)"
        var config: [String: Any] = [:]
        if let data = fm.contents(atPath: opencodeConfigPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = parsed
        }

        var plugins = config["plugin"] as? [String] ?? []
        plugins.removeAll {
            $0.contains("vibe-island")
                || $0.contains(HookId.current)
                || HookId.legacy.contains(where: $0.contains)
        }
        plugins.append(pluginReference)
        config["plugin"] = plugins

        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            _ = fm.createFile(atPath: opencodeConfigPath, contents: data)
        }
        return true
    }

    static func uninstallOpencodePlugin(fm: FileManager) {
        try? fm.removeItem(atPath: opencodePluginPath)

        guard let data = fm.contents(atPath: opencodeConfigPath),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var plugins = config["plugin"] as? [String] else { return }

        plugins.removeAll {
            $0.contains(HookId.current) || HookId.legacy.contains(where: $0.contains)
        }
        config["plugin"] = plugins.isEmpty ? nil : plugins

        if let encoded = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            _ = fm.createFile(atPath: opencodeConfigPath, contents: encoded)
        }
    }

    static func isOpencodePluginInstalled(fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: opencodePluginPath),
              let data = fm.contents(atPath: opencodeConfigPath),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = config["plugin"] as? [String] else { return false }
        guard plugins.contains(where: { $0.contains(HookId.current) }) else { return false }

        if let existing = fm.contents(atPath: opencodePluginPath),
           let string = String(data: existing, encoding: .utf8) {
            return string.contains("// version: \(opencodePluginVersion)")
        }
        return false
    }
}
