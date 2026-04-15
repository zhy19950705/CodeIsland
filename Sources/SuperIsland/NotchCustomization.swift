import AppKit
import Foundation

/// Per-screen notch geometry persisted independently so external displays
/// can keep different width and position tuning.
struct ScreenNotchGeometry: Codable, Equatable {
    /// `0` means "follow automatic width detection".
    var customWidth: CGFloat = 0
    var horizontalOffset: CGFloat = 0
    var notchHeight: CGFloat = 38

    static let `default` = ScreenNotchGeometry()
}

/// Single persisted value carrying all notch customization state.
struct NotchCustomization: Codable, Equatable {
    var hardwareNotchMode: HardwareNotchMode = .auto
    var screenGeometries: [String: ScreenNotchGeometry] = [:]
    var defaultGeometry: ScreenNotchGeometry = .default

    static let `default` = NotchCustomization()

    /// Unknown displays fall back to the shared default geometry until edited explicitly.
    func geometry(for screenID: String) -> ScreenNotchGeometry {
        screenGeometries[screenID] ?? defaultGeometry
    }

    /// Write-through helper keeps call sites small when editing one screen at a time.
    mutating func updateGeometry(for screenID: String, _ body: (inout ScreenNotchGeometry) -> Void) {
        var geometry = geometry(for: screenID)
        body(&geometry)
        screenGeometries[screenID] = geometry
    }

    private enum CodingKeys: String, CodingKey {
        case hardwareNotchMode
        case screenGeometries
        case defaultGeometry
        case customWidth
        case horizontalOffset
        case notchHeight
    }

    init() {}

    /// Decode both the new per-screen schema and the legacy single-screen width/offset keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hardwareNotchMode = try container.decodeIfPresent(HardwareNotchMode.self, forKey: .hardwareNotchMode) ?? .auto
        screenGeometries = try container.decodeIfPresent([String: ScreenNotchGeometry].self, forKey: .screenGeometries) ?? [:]

        if let decodedDefault = try container.decodeIfPresent(ScreenNotchGeometry.self, forKey: .defaultGeometry) {
            defaultGeometry = decodedDefault
        } else {
            var migrated = ScreenNotchGeometry.default
            migrated.customWidth = try container.decodeIfPresent(CGFloat.self, forKey: .customWidth) ?? 0
            migrated.horizontalOffset = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalOffset) ?? 0
            migrated.notchHeight = try container.decodeIfPresent(CGFloat.self, forKey: .notchHeight) ?? ScreenNotchGeometry.default.notchHeight
            defaultGeometry = migrated
        }
    }

    /// Persist only the modern schema while keeping decode backwards compatible.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hardwareNotchMode, forKey: .hardwareNotchMode)
        try container.encode(screenGeometries, forKey: .screenGeometries)
        try container.encode(defaultGeometry, forKey: .defaultGeometry)
    }
}

extension NSScreen {
    /// Stable enough identifier for persisting per-screen geometry.
    var notchScreenID: String {
        if let displayID {
            return "display-\(displayID)"
        }
        let signature = ScreenDetector.signature(for: self)
        return "screen-\(localizedName)-\(signature)"
    }
}
