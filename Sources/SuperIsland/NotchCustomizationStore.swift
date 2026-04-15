import Foundation
import Observation

private let notchCustomizationDefaultsKey = "superIsland.notchCustomization.v1"

/// Central source of truth for notch geometry customizations and live edit state.
@MainActor
@Observable
final class NotchCustomizationStore {
    static let shared = NotchCustomizationStore()
    nonisolated static var defaultsKey: String { notchCustomizationDefaultsKey }

    var customization: NotchCustomization
    var isEditing = false

    private var editDraftOrigin: NotchCustomization?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let loaded = Self.load(from: defaults) {
            self.customization = loaded
        } else {
            self.customization = Self.migratedInitialCustomization(from: defaults)
            _ = save()
        }
    }

    /// Apply a top-level customization mutation and immediately persist it for live preview.
    func update(_ mutation: (inout NotchCustomization) -> Void) {
        mutation(&customization)
        save()
        notifyChange()
    }

    /// Convenience wrapper for the common per-screen geometry editing path.
    func updateGeometry(for screenID: String, _ mutation: (inout ScreenNotchGeometry) -> Void) {
        update { $0.updateGeometry(for: screenID, mutation) }
    }

    /// Snapshot the original geometry so cancel can revert the full editing session.
    func enterEditMode() {
        editDraftOrigin = customization
        isEditing = true
        notifyEditingChange()
    }

    /// Commit ends the session but keeps the already-persisted live edits in place.
    func commitEdit() {
        editDraftOrigin = nil
        isEditing = false
        save()
        notifyEditingChange()
        notifyChange()
    }

    /// Restore the original snapshot so aborted edits never leak into future launches.
    func cancelEdit() {
        if let editDraftOrigin {
            customization = editDraftOrigin
            save()
        }
        editDraftOrigin = nil
        isEditing = false
        notifyEditingChange()
        notifyChange()
    }

    @discardableResult
    func save() -> Bool {
        guard let data = try? JSONEncoder().encode(customization) else { return false }
        defaults.set(data, forKey: notchCustomizationDefaultsKey)
        // Keep legacy single-screen settings in sync as a compatibility fallback.
        defaults.set(Int(customization.defaultGeometry.customWidth.rounded()), forKey: SettingsKey.notchWidthOverride)
        defaults.set(Double(customization.defaultGeometry.horizontalOffset), forKey: SettingsKey.panelHorizontalOffset)
        defaults.set(customization.hardwareNotchMode.rawValue, forKey: SettingsKey.hardwareNotchMode)
        return true
    }

    /// Nonisolated load keeps read-only call sites usable from window and detector helpers.
    nonisolated static func load(from defaults: UserDefaults = .standard) -> NotchCustomization? {
        guard let data = defaults.data(forKey: notchCustomizationDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(NotchCustomization.self, from: data)
    }

    /// Seed the new store from older width and offset settings so upgrades keep the previous layout.
    private static func migratedInitialCustomization(from defaults: UserDefaults) -> NotchCustomization {
        var customization = NotchCustomization.default
        customization.hardwareNotchMode = HardwareNotchMode(
            rawValue: defaults.string(forKey: SettingsKey.hardwareNotchMode) ?? HardwareNotchMode.auto.rawValue
        ) ?? .auto
        customization.defaultGeometry.customWidth = CGFloat(defaults.integer(forKey: SettingsKey.notchWidthOverride))
        customization.defaultGeometry.horizontalOffset = CGFloat(defaults.double(forKey: SettingsKey.panelHorizontalOffset))
        customization.defaultGeometry.notchHeight = ScreenNotchGeometry.default.notchHeight
        return customization
    }

    /// Local notifications let the window layer refresh without tightly coupling to SwiftUI state.
    private func notifyChange() {
        NotificationCenter.default.post(name: .superIslandNotchCustomizationDidChange, object: self)
    }

    private func notifyEditingChange() {
        NotificationCenter.default.post(name: .superIslandNotchEditingDidChange, object: self)
    }
}

extension Notification.Name {
    static let superIslandNotchCustomizationDidChange = Notification.Name("SuperIslandNotchCustomizationDidChange")
    static let superIslandNotchEditingDidChange = Notification.Name("SuperIslandNotchEditingDidChange")
}
