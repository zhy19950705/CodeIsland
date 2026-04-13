import AppKit
import Combine
import Foundation

enum ScreenSelectionMode: String, Codable {
    case automatic
    case specificScreen
}

struct ScreenIdentifier: Codable, Equatable, Hashable {
    let displayID: CGDirectDisplayID?
    let localizedName: String

    init(displayID: CGDirectDisplayID?, localizedName: String) {
        self.displayID = displayID
        self.localizedName = localizedName
    }

    init(screen: NSScreen) {
        self.init(displayID: screen.displayID, localizedName: screen.localizedName)
    }

    func matches(displayID: CGDirectDisplayID?, localizedName: String) -> Bool {
        if let savedID = self.displayID, let displayID, savedID == displayID {
            return true
        }
        return self.localizedName == localizedName
    }

    func matches(_ screen: NSScreen) -> Bool {
        matches(displayID: screen.displayID, localizedName: screen.localizedName)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltinDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    static var builtin: NSScreen? {
        screens.first(where: \.isBuiltinDisplay) ?? NSScreen.main
    }
}

@MainActor
final class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()

    @Published private(set) var availableScreens: [NSScreen] = []
    @Published private(set) var selectedScreen: NSScreen?
    @Published private(set) var selectionMode: ScreenSelectionMode = .automatic

    var preferenceSignature: String {
        switch selectionMode {
        case .automatic:
            return ScreenSelectionMode.automatic.rawValue
        case .specificScreen:
            let identifier = savedIdentifier
            return [
                ScreenSelectionMode.specificScreen.rawValue,
                identifier?.displayID.map(String.init) ?? "nil",
                identifier?.localizedName ?? ""
            ].joined(separator: "|")
        }
    }

    private let defaults = UserDefaults.standard
    private var savedIdentifier: ScreenIdentifier?
    private var screenObserver: NSObjectProtocol?

    private init() {
        loadPreferences()
        refreshScreens()
        migrateLegacyPreferenceIfNeeded()
        refreshScreens()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreens()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func refreshScreens() {
        availableScreens = NSScreen.screens
        selectedScreen = resolveSelectedScreen()
    }

    func selectScreen(_ screen: NSScreen) {
        selectionMode = .specificScreen
        savedIdentifier = ScreenIdentifier(screen: screen)
        selectedScreen = screen
        savePreferences()
    }

    func selectAutomatic() {
        selectionMode = .automatic
        savedIdentifier = nil
        selectedScreen = resolveSelectedScreen()
        savePreferences()
    }

    func isSelected(_ screen: NSScreen) -> Bool {
        guard selectionMode == .specificScreen, let savedIdentifier else { return false }
        return savedIdentifier.matches(screen)
    }

    private func resolveSelectedScreen() -> NSScreen? {
        guard !availableScreens.isEmpty else { return nil }

        switch selectionMode {
        case .automatic:
            return ScreenDetector.preferredScreen
        case .specificScreen:
            if let savedIdentifier,
               let matchingScreen = availableScreens.first(where: { savedIdentifier.matches($0) }) {
                return matchingScreen
            }
            return ScreenDetector.preferredScreen
        }
    }

    private func loadPreferences() {
        if let rawMode = defaults.string(forKey: SettingsKey.screenSelectionMode),
           let mode = ScreenSelectionMode(rawValue: rawMode) {
            selectionMode = mode
        }

        if let data = defaults.data(forKey: SettingsKey.selectedScreenIdentifier),
           let identifier = try? JSONDecoder().decode(ScreenIdentifier.self, from: data) {
            savedIdentifier = identifier
        }
    }

    private func savePreferences() {
        defaults.set(selectionMode.rawValue, forKey: SettingsKey.screenSelectionMode)

        if let savedIdentifier,
           let encoded = try? JSONEncoder().encode(savedIdentifier) {
            defaults.set(encoded, forKey: SettingsKey.selectedScreenIdentifier)
        } else {
            defaults.removeObject(forKey: SettingsKey.selectedScreenIdentifier)
        }
    }

    private func migrateLegacyPreferenceIfNeeded() {
        let hasMigratedMode = defaults.object(forKey: SettingsKey.screenSelectionMode) != nil
        let hasMigratedIdentifier = defaults.object(forKey: SettingsKey.selectedScreenIdentifier) != nil
        guard !hasMigratedMode && !hasMigratedIdentifier else { return }

        guard let legacyChoice = defaults.object(forKey: SettingsKey.displayChoice) as? String else {
            savePreferences()
            return
        }

        switch legacyChoice {
        case "auto":
            selectionMode = .automatic
            savedIdentifier = nil
        case "builtin":
            if let builtin = NSScreen.builtin {
                selectionMode = .specificScreen
                savedIdentifier = ScreenIdentifier(screen: builtin)
            }
        case "main":
            if let mainScreen = NSScreen.main {
                selectionMode = .specificScreen
                savedIdentifier = ScreenIdentifier(screen: mainScreen)
            }
        default:
            if legacyChoice.hasPrefix("screen_"),
               let index = Int(legacyChoice.dropFirst("screen_".count)),
               availableScreens.indices.contains(index) {
                selectionMode = .specificScreen
                savedIdentifier = ScreenIdentifier(screen: availableScreens[index])
            } else {
                selectionMode = .automatic
                savedIdentifier = nil
            }
        }

        savePreferences()
    }
}
