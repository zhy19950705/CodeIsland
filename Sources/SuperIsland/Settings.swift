import AppKit
import ServiceManagement

enum AppVersion {
    /// Update this each release. Used as fallback when Info.plist is unavailable (debug builds).
    static let fallback = "0.0.11"

    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
    }
}

enum DisplayMode: String, CaseIterable {
    case auto
    case notch
    case menuBar
}

enum SettingsKey {
    // Language
    static let appLanguage = "appLanguage"                 // "system", "en", "zh"

    // General - System
    static let launchAtLogin = "launchAtLogin"
    static let displayChoice = "displayChoice"             // Legacy key kept for migration
    static let displayMode = "displayMode"
    static let menuBarShowDetail = "menuBarShowDetail"
    static let screenSelectionMode = "screenSelectionMode"
    static let selectedScreenIdentifier = "selectedScreenIdentifier"
    static let allowHorizontalDrag = "allowHorizontalDrag"
    static let panelHorizontalOffset = "panelHorizontalOffset"

    // General - Behavior
    static let hideInFullscreen = "hideInFullscreen"
    static let hideWhenNoSession = "hideWhenNoSession"
    static let smartSuppress = "smartSuppress"
    static let collapseOnMouseLeave = "collapseOnMouseLeave"
    static let hoverActivationDelay = "hoverActivationDelay"
    static let fullscreenHoverActivationDelay = "fullscreenHoverActivationDelay"
    static let fullscreenRevealZoneHeight = "fullscreenRevealZoneHeight"
    static let fullscreenRevealZoneHorizontalInset = "fullscreenRevealZoneHorizontalInset"
    static let completionCardDisplaySeconds = "completionCardDisplaySeconds"
    static let sessionTimeout = "sessionTimeout"

    // Display
    static let maxPanelHeight = "maxPanelHeight"
    static let notchWidthOverride = "notchWidthOverride"
    static let maxVisibleSessions = "maxVisibleSessions"
    static let contentFontSize = "contentFontSize"
    static let aiMessageLines = "aiMessageLines"
    static let showAgentDetails = "showAgentDetails"

    // Sound
    static let soundEnabled = "soundEnabled"
    static let soundVolume = "soundVolume"
    static let soundSessionStart = "soundSessionStart"
    static let soundTaskComplete = "soundTaskComplete"
    static let soundTaskError = "soundTaskError"
    static let soundApprovalNeeded = "soundApprovalNeeded"
    static let soundPromptSubmit = "soundPromptSubmit"
    static let soundBoot = "soundBoot"
    static let soundPackID = "soundPackID"

    // Shortcuts (per-action: shortcut_{action}_enabled, shortcut_{action}_keyCode, shortcut_{action}_modifiers)
    static func shortcutEnabled(_ action: String) -> String { "shortcut_\(action)_enabled" }
    static func shortcutKeyCode(_ action: String) -> String { "shortcut_\(action)_keyCode" }
    static func shortcutModifiers(_ action: String) -> String { "shortcut_\(action)_modifiers" }

    // Advanced
    static let maxToolHistory = "maxToolHistory"

    // Mascot
    static let mascotSpeed = "mascotSpeed"
    static let mascotOverridesVersion = "mascotOverridesVersion"
    static func mascotOverride(_ clientSource: String) -> String { "mascotOverride_\(clientSource)" }

    // Session grouping
    static let sessionGroupingMode = "sessionGroupingMode"

    // Tool status display
    static let showToolStatus = "showToolStatus"              // true = detailed, false = simple

}

struct SettingsDefaults {
    static let displayChoice = "auto"
    static let displayMode = DisplayMode.menuBar.rawValue
    static let menuBarShowDetail = false
    static let screenSelectionMode = "automatic"
    static let allowHorizontalDrag = false
    static let panelHorizontalOffset = 0.0
    static let hideInFullscreen = true
    static let hideWhenNoSession = false
    static let smartSuppress = true
    static let collapseOnMouseLeave = true
    static let hoverActivationDelay = 0.24
    static let fullscreenHoverActivationDelay = 0.18
    static let fullscreenRevealZoneHeight = 8.0
    static let fullscreenRevealZoneHorizontalInset = 36.0
    static let completionCardDisplaySeconds = 10
    static let sessionTimeout = 1440

    static let maxPanelHeight = 560
    static let notchWidthOverride = 0
    static let maxVisibleSessions = 5
    static let contentFontSize = 11
    static let aiMessageLines = 1
    static let showAgentDetails = false

    static let soundEnabled = false
    static let soundVolume = 50
    static let soundSessionStart = true
    static let soundTaskComplete = true
    static let soundTaskError = true
    static let soundApprovalNeeded = true
    static let soundPromptSubmit = false
    static let soundBoot = true
    static let soundPackID = SoundPackCatalog.defaultPackID

    static let maxToolHistory = 20

    static let mascotSpeed = 100  // percentage: 0–300, 0 = silent

    static let sessionGroupingMode = "project"

    static let showToolStatus = true
}

@MainActor
class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            SettingsKey.displayChoice: SettingsDefaults.displayChoice,
            SettingsKey.displayMode: SettingsDefaults.displayMode,
            SettingsKey.menuBarShowDetail: SettingsDefaults.menuBarShowDetail,
            SettingsKey.screenSelectionMode: SettingsDefaults.screenSelectionMode,
            SettingsKey.allowHorizontalDrag: SettingsDefaults.allowHorizontalDrag,
            SettingsKey.panelHorizontalOffset: SettingsDefaults.panelHorizontalOffset,
            SettingsKey.hideInFullscreen: SettingsDefaults.hideInFullscreen,
            SettingsKey.hideWhenNoSession: SettingsDefaults.hideWhenNoSession,
            SettingsKey.smartSuppress: SettingsDefaults.smartSuppress,
            SettingsKey.collapseOnMouseLeave: SettingsDefaults.collapseOnMouseLeave,
            SettingsKey.hoverActivationDelay: SettingsDefaults.hoverActivationDelay,
            SettingsKey.fullscreenHoverActivationDelay: SettingsDefaults.fullscreenHoverActivationDelay,
            SettingsKey.fullscreenRevealZoneHeight: SettingsDefaults.fullscreenRevealZoneHeight,
            SettingsKey.fullscreenRevealZoneHorizontalInset: SettingsDefaults.fullscreenRevealZoneHorizontalInset,
            SettingsKey.completionCardDisplaySeconds: SettingsDefaults.completionCardDisplaySeconds,
            SettingsKey.sessionTimeout: SettingsDefaults.sessionTimeout,
            SettingsKey.maxPanelHeight: SettingsDefaults.maxPanelHeight,
            SettingsKey.notchWidthOverride: SettingsDefaults.notchWidthOverride,
            SettingsKey.maxVisibleSessions: SettingsDefaults.maxVisibleSessions,
            SettingsKey.contentFontSize: SettingsDefaults.contentFontSize,
            SettingsKey.aiMessageLines: SettingsDefaults.aiMessageLines,
            SettingsKey.showAgentDetails: SettingsDefaults.showAgentDetails,
            SettingsKey.soundEnabled: SettingsDefaults.soundEnabled,
            SettingsKey.soundVolume: SettingsDefaults.soundVolume,
            SettingsKey.soundSessionStart: SettingsDefaults.soundSessionStart,
            SettingsKey.soundTaskComplete: SettingsDefaults.soundTaskComplete,
            SettingsKey.soundTaskError: SettingsDefaults.soundTaskError,
            SettingsKey.soundApprovalNeeded: SettingsDefaults.soundApprovalNeeded,
            SettingsKey.soundPromptSubmit: SettingsDefaults.soundPromptSubmit,
            SettingsKey.soundBoot: SettingsDefaults.soundBoot,
            SettingsKey.soundPackID: SettingsDefaults.soundPackID,
            SettingsKey.maxToolHistory: SettingsDefaults.maxToolHistory,
            SettingsKey.mascotSpeed: SettingsDefaults.mascotSpeed,
            SettingsKey.mascotOverridesVersion: 0,
            SettingsKey.sessionGroupingMode: SettingsDefaults.sessionGroupingMode,
            SettingsKey.showToolStatus: SettingsDefaults.showToolStatus,
        ])
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                // Login item update may fail silently in sandboxed environments
            }
        }
    }

    var displayChoice: String {
        get { defaults.string(forKey: SettingsKey.displayChoice) ?? SettingsDefaults.displayChoice }
        set { defaults.set(newValue, forKey: SettingsKey.displayChoice) }
    }

    var displayMode: DisplayMode {
        get {
            guard let rawValue = defaults.string(forKey: SettingsKey.displayMode),
                  let mode = DisplayMode(rawValue: rawValue) else {
                return .menuBar
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: SettingsKey.displayMode) }
    }

    var menuBarShowDetail: Bool {
        get {
            if defaults.object(forKey: SettingsKey.menuBarShowDetail) == nil {
                return SettingsDefaults.menuBarShowDetail
            }
            return defaults.bool(forKey: SettingsKey.menuBarShowDetail)
        }
        set { defaults.set(newValue, forKey: SettingsKey.menuBarShowDetail) }
    }

    var allowHorizontalDrag: Bool {
        get { defaults.bool(forKey: SettingsKey.allowHorizontalDrag) }
        set { defaults.set(newValue, forKey: SettingsKey.allowHorizontalDrag) }
    }

    var panelHorizontalOffset: Double {
        get { defaults.double(forKey: SettingsKey.panelHorizontalOffset) }
        set { defaults.set(newValue, forKey: SettingsKey.panelHorizontalOffset) }
    }

    var hideInFullscreen: Bool {
        get { defaults.bool(forKey: SettingsKey.hideInFullscreen) }
        set { defaults.set(newValue, forKey: SettingsKey.hideInFullscreen) }
    }

    var hideWhenNoSession: Bool {
        get { defaults.bool(forKey: SettingsKey.hideWhenNoSession) }
        set { defaults.set(newValue, forKey: SettingsKey.hideWhenNoSession) }
    }

    var smartSuppress: Bool {
        get { defaults.bool(forKey: SettingsKey.smartSuppress) }
        set { defaults.set(newValue, forKey: SettingsKey.smartSuppress) }
    }

    var collapseOnMouseLeave: Bool {
        get { defaults.bool(forKey: SettingsKey.collapseOnMouseLeave) }
        set { defaults.set(newValue, forKey: SettingsKey.collapseOnMouseLeave) }
    }

    var hoverActivationDelay: Double {
        get { defaults.double(forKey: SettingsKey.hoverActivationDelay) }
        set { defaults.set(newValue, forKey: SettingsKey.hoverActivationDelay) }
    }

    var fullscreenHoverActivationDelay: Double {
        get { defaults.double(forKey: SettingsKey.fullscreenHoverActivationDelay) }
        set { defaults.set(newValue, forKey: SettingsKey.fullscreenHoverActivationDelay) }
    }

    var fullscreenRevealZoneHeight: Double {
        get { defaults.double(forKey: SettingsKey.fullscreenRevealZoneHeight) }
        set { defaults.set(newValue, forKey: SettingsKey.fullscreenRevealZoneHeight) }
    }

    var fullscreenRevealZoneHorizontalInset: Double {
        get { defaults.double(forKey: SettingsKey.fullscreenRevealZoneHorizontalInset) }
        set { defaults.set(newValue, forKey: SettingsKey.fullscreenRevealZoneHorizontalInset) }
    }

    var completionCardDisplaySeconds: Int {
        get {
            let value = defaults.integer(forKey: SettingsKey.completionCardDisplaySeconds)
            return max(1, value)
        }
        set { defaults.set(max(1, newValue), forKey: SettingsKey.completionCardDisplaySeconds) }
    }

    var sessionTimeout: Int {
        get { defaults.integer(forKey: SettingsKey.sessionTimeout) }
        set { defaults.set(newValue, forKey: SettingsKey.sessionTimeout) }
    }

    var maxPanelHeight: Int {
        get { defaults.integer(forKey: SettingsKey.maxPanelHeight) }
        set { defaults.set(newValue, forKey: SettingsKey.maxPanelHeight) }
    }

    var notchWidthOverride: Int {
        get { defaults.integer(forKey: SettingsKey.notchWidthOverride) }
        set { defaults.set(max(0, newValue), forKey: SettingsKey.notchWidthOverride) }
    }

    var contentFontSize: Int {
        get { defaults.integer(forKey: SettingsKey.contentFontSize) }
        set { defaults.set(newValue, forKey: SettingsKey.contentFontSize) }
    }

    var showAgentDetails: Bool {
        get { defaults.bool(forKey: SettingsKey.showAgentDetails) }
        set { defaults.set(newValue, forKey: SettingsKey.showAgentDetails) }
    }

    var maxToolHistory: Int {
        get { defaults.integer(forKey: SettingsKey.maxToolHistory) }
        set { defaults.set(newValue, forKey: SettingsKey.maxToolHistory) }
    }

    var sessionGroupingMode: String {
        get { defaults.string(forKey: SettingsKey.sessionGroupingMode) ?? SettingsDefaults.sessionGroupingMode }
        set { defaults.set(newValue, forKey: SettingsKey.sessionGroupingMode) }
    }
}

// MARK: - Shortcut Actions

struct ShortcutBinding {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    static func keyCodeToString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 111: "F12", 103: "F11",
            118: "F4", 120: "F2", 122: "F1",
        ]
        return map[code] ?? "?"
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case togglePanel
    case approve
    case approveAlways
    case deny
    case skipQuestion
    case jumpToTerminal

    var id: String { rawValue }

    var defaultBinding: ShortcutBinding? {
        switch self {
        case .togglePanel:    return ShortcutBinding(keyCode: 34, modifiers: [.command, .shift]) // ⌘⇧I
        case .approve:        return ShortcutBinding(keyCode: 0,  modifiers: [.command, .shift]) // ⌘⇧A
        case .deny:           return ShortcutBinding(keyCode: 2,  modifiers: [.command, .shift]) // ⌘⇧D
        case .approveAlways:  return nil
        case .skipQuestion:   return nil
        case .jumpToTerminal: return nil
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .togglePanel: return true
        default: return false
        }
    }

    var isEnabled: Bool {
        let key = SettingsKey.shortcutEnabled(rawValue)
        if UserDefaults.standard.object(forKey: key) == nil { return defaultEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    var binding: ShortcutBinding {
        let kcKey = SettingsKey.shortcutKeyCode(rawValue)
        let modKey = SettingsKey.shortcutModifiers(rawValue)
        let fallback = defaultBinding ?? ShortcutBinding(keyCode: 0, modifiers: [.command, .shift])
        let keyCode = UInt16(UserDefaults.standard.object(forKey: kcKey) != nil
            ? UserDefaults.standard.integer(forKey: kcKey)
            : Int(fallback.keyCode))
        let modRaw = UserDefaults.standard.object(forKey: modKey) != nil
            ? UInt(UserDefaults.standard.integer(forKey: modKey))
            : fallback.modifiers.rawValue
        return ShortcutBinding(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: modRaw).intersection(.deviceIndependentFlagsMask)
        )
    }

    func setBinding(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: SettingsKey.shortcutKeyCode(rawValue))
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: SettingsKey.shortcutModifiers(rawValue))
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKey.shortcutEnabled(rawValue))
    }

    /// Returns the other action that conflicts with this one's binding, if any.
    func conflictingAction() -> ShortcutAction? {
        guard isEnabled else { return nil }
        let myBinding = binding
        for other in Self.allCases where other != self && other.isEnabled {
            let otherBinding = other.binding
            if otherBinding.keyCode == myBinding.keyCode && otherBinding.modifiers == myBinding.modifiers {
                return other
            }
        }
        return nil
    }
}
