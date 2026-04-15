import Foundation

extension SettingsKey {
    /// Persists whether the selected display should use the physical notch
    /// or a virtual notch layout.
    static let hardwareNotchMode = "hardwareNotchMode"
}

extension SettingsDefaults {
    /// Default to the real hardware notch so existing installs keep the same behavior.
    static let hardwareNotchMode = HardwareNotchMode.auto.rawValue
}

@MainActor
extension SettingsManager {
    /// Resolve the stored notch mode defensively so older defaults keep working.
    var hardwareNotchMode: HardwareNotchMode {
        get {
            guard let rawValue = defaults.string(forKey: SettingsKey.hardwareNotchMode),
                  let mode = HardwareNotchMode(rawValue: rawValue) else {
                return .auto
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: SettingsKey.hardwareNotchMode)
        }
    }
}
