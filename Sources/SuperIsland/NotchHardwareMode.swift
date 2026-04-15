import Foundation

/// Controls whether SuperIsland follows the real hardware notch or renders
/// a virtual notch that can appear on any display.
enum HardwareNotchMode: String, CaseIterable, Codable {
    case auto
    case forceVirtual
}
