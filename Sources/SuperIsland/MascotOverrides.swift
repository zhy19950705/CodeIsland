import Foundation

enum MascotOverrides {
    static let supportedSources: [String] = [
        "claude",
        "codex",
        "gemini",
        "cursor",
        "copilot",
        "qoder",
        "droid",
        "codebuddy",
        "opencode",
    ]

    static func effectiveSource(for clientSource: String, defaults: UserDefaults = .standard) -> String {
        override(for: clientSource, defaults: defaults) ?? clientSource
    }

    static func override(for clientSource: String, defaults: UserDefaults = .standard) -> String? {
        guard supportedSources.contains(clientSource) else { return nil }
        guard let value = defaults.string(forKey: SettingsKey.mascotOverride(clientSource)),
              supportedSources.contains(value),
              value != clientSource else {
            return nil
        }
        return value
    }

    static func setOverride(_ mascotSource: String?, for clientSource: String, defaults: UserDefaults = .standard) {
        guard supportedSources.contains(clientSource) else { return }

        if let mascotSource,
           supportedSources.contains(mascotSource),
           mascotSource != clientSource {
            defaults.set(mascotSource, forKey: SettingsKey.mascotOverride(clientSource))
        } else {
            defaults.removeObject(forKey: SettingsKey.mascotOverride(clientSource))
        }

        defaults.set(defaults.integer(forKey: SettingsKey.mascotOverridesVersion) + 1, forKey: SettingsKey.mascotOverridesVersion)
    }

    static func allOverrides(defaults: UserDefaults = .standard) -> [String: String] {
        supportedSources.reduce(into: [String: String]()) { result, source in
            if let override = override(for: source, defaults: defaults) {
                result[source] = override
            }
        }
    }

    static func customizedCount(defaults: UserDefaults = .standard) -> Int {
        allOverrides(defaults: defaults).count
    }

    static func resetAll(defaults: UserDefaults = .standard) {
        for source in supportedSources {
            defaults.removeObject(forKey: SettingsKey.mascotOverride(source))
        }
        defaults.set(defaults.integer(forKey: SettingsKey.mascotOverridesVersion) + 1, forKey: SettingsKey.mascotOverridesVersion)
    }
}
