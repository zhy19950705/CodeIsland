import Foundation

/// Tracks whether the one-time first-launch guidance still needs to be shown.
struct FirstLaunchExperience {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Consumes the pending first-launch presentation so the UI only appears once on a fresh install.
    mutating func consumePendingPresentation() -> Bool {
        if defaults.bool(forKey: SettingsKey.firstLaunchExperiencePresented) {
            return false
        }

        defaults.set(true, forKey: SettingsKey.firstLaunchExperiencePresented)
        return true
    }
}
