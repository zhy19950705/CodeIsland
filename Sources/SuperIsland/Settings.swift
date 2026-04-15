import AppKit
import ServiceManagement

enum AppVersion {
    /// Update this each release. Used as fallback when Info.plist is unavailable (debug builds).
    static let fallback = "1.0.16"

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
    static let hookAutoApproveTools = "hookAutoApproveTools"
    static let displayModeCompatibilityMigration = "displayModeCompatibilityMigration"

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
    static let mascotOverridesVersion = 0

    static let sessionGroupingMode = "project"

    static let showToolStatus = true

    static let registeredValues: [String: Any] = [
        SettingsKey.displayChoice: displayChoice,
        SettingsKey.displayMode: displayMode,
        SettingsKey.menuBarShowDetail: menuBarShowDetail,
        SettingsKey.screenSelectionMode: screenSelectionMode,
        SettingsKey.allowHorizontalDrag: allowHorizontalDrag,
        SettingsKey.panelHorizontalOffset: panelHorizontalOffset,
        SettingsKey.hideInFullscreen: hideInFullscreen,
        SettingsKey.hideWhenNoSession: hideWhenNoSession,
        SettingsKey.smartSuppress: smartSuppress,
        SettingsKey.collapseOnMouseLeave: collapseOnMouseLeave,
        SettingsKey.hoverActivationDelay: hoverActivationDelay,
        SettingsKey.fullscreenHoverActivationDelay: fullscreenHoverActivationDelay,
        SettingsKey.fullscreenRevealZoneHeight: fullscreenRevealZoneHeight,
        SettingsKey.fullscreenRevealZoneHorizontalInset: fullscreenRevealZoneHorizontalInset,
        SettingsKey.completionCardDisplaySeconds: completionCardDisplaySeconds,
        SettingsKey.sessionTimeout: sessionTimeout,
        SettingsKey.maxPanelHeight: maxPanelHeight,
        SettingsKey.notchWidthOverride: notchWidthOverride,
        SettingsKey.hardwareNotchMode: hardwareNotchMode,
        SettingsKey.maxVisibleSessions: maxVisibleSessions,
        SettingsKey.contentFontSize: contentFontSize,
        SettingsKey.aiMessageLines: aiMessageLines,
        SettingsKey.showAgentDetails: showAgentDetails,
        SettingsKey.soundEnabled: soundEnabled,
        SettingsKey.soundVolume: soundVolume,
        SettingsKey.soundSessionStart: soundSessionStart,
        SettingsKey.soundTaskComplete: soundTaskComplete,
        SettingsKey.soundTaskError: soundTaskError,
        SettingsKey.soundApprovalNeeded: soundApprovalNeeded,
        SettingsKey.soundPromptSubmit: soundPromptSubmit,
        SettingsKey.soundBoot: soundBoot,
        SettingsKey.soundPackID: soundPackID,
        SettingsKey.maxToolHistory: maxToolHistory,
        SettingsKey.mascotSpeed: mascotSpeed,
        SettingsKey.mascotOverridesVersion: mascotOverridesVersion,
        SettingsKey.sessionGroupingMode: sessionGroupingMode,
        SettingsKey.showToolStatus: showToolStatus,
    ]
}

@MainActor
class SettingsManager {
    static let shared = SettingsManager()

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, hasPhysicalNotch: Bool? = nil) {
        self.defaults = defaults
        defaults.register(defaults: SettingsDefaults.registeredValues)
        migrateDisplayModeCompatibilityIfNeeded(hasPhysicalNotch: hasPhysicalNotch ?? ScreenDetector.hasNotch)
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

    private func migrateDisplayModeCompatibilityIfNeeded(hasPhysicalNotch: Bool) {
        guard defaults.object(forKey: SettingsKey.displayModeCompatibilityMigration) == nil else { return }
        defer { defaults.set(AppVersion.current, forKey: SettingsKey.displayModeCompatibilityMigration) }

        guard !hasPhysicalNotch else { return }
        guard defaults.string(forKey: SettingsKey.displayMode) == DisplayMode.notch.rawValue else { return }

        let legacyChoice = defaults.string(forKey: SettingsKey.displayChoice)
        guard legacyChoice == nil || legacyChoice == "auto" else { return }

        defaults.set(DisplayMode.menuBar.rawValue, forKey: SettingsKey.displayMode)
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
