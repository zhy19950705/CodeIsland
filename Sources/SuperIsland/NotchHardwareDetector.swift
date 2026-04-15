import AppKit

/// Pure helpers for deriving notch metrics from the selected display.
enum NotchHardwareDetector {
    static let minVirtualWidth: CGFloat = 160
    static let maxVirtualWidth: CGFloat = 240
    static let minNotchHeight: CGFloat = 20
    static let maxNotchHeight: CGFloat = 80

    /// `safeAreaInsets.top` is the most robust signal for a hardware notch on modern macOS.
    static func hasHardwareNotch(on screen: NSScreen?, mode: HardwareNotchMode) -> Bool {
        switch mode {
        case .forceVirtual:
            return false
        case .auto:
            guard let screen else { return false }
            if #available(macOS 12.0, *) {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
            return false
        }
    }

    /// Keep virtual notch width proportional to the display, but clamp it so it stays usable.
    static func fallbackVirtualWidth(for screenWidth: CGFloat) -> CGFloat {
        min(max(screenWidth * 0.14, minVirtualWidth), maxVirtualWidth)
    }

    /// Prefer a user override first, then measured hardware width, then the virtual fallback.
    static func resolvedNotchWidth(
        on screen: NSScreen,
        mode: HardwareNotchMode,
        override: CGFloat?
    ) -> CGFloat {
        if let override, override > 0 {
            return override
        }

        guard hasHardwareNotch(on: screen, mode: mode) else {
            return fallbackVirtualWidth(for: screen.frame.width)
        }

        if #available(macOS 12.0, *) {
            let insets = screen.safeAreaInsets
            let measuredWidth = screen.frame.width - insets.left - insets.right
            if measuredWidth > 0 {
                return measuredWidth
            }
        }

        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        if leftWidth > 0 || rightWidth > 0 {
            return max(0, screen.frame.width - leftWidth - rightWidth)
        }

        return fallbackVirtualWidth(for: screen.frame.width)
    }

    /// When virtual mode is enabled, still keep the island aligned to the menu bar height.
    static func resolvedTopBarHeight(
        on screen: NSScreen,
        mode: HardwareNotchMode
    ) -> CGFloat {
        if #available(macOS 12.0, *),
           hasHardwareNotch(on: screen, mode: mode),
           screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if menuBarHeight > 5 {
            return menuBarHeight
        }

        if let mainScreen = NSScreen.main {
            let mainMenuBarHeight = mainScreen.frame.maxY - mainScreen.visibleFrame.maxY
            if mainMenuBarHeight > 5 {
                return mainMenuBarHeight
            }
        }

        return 25
    }

    /// Clamp render-time horizontal motion so a saved offset from a larger display
    /// cannot push the island outside the current screen.
    static func clampedHorizontalOffset(
        storedOffset: CGFloat,
        runtimeWidth: CGFloat,
        screenFrame: CGRect
    ) -> CGFloat {
        let centeredX = screenFrame.midX - runtimeWidth / 2
        let minOffset = screenFrame.minX - centeredX
        let maxOffset = screenFrame.maxX - centeredX - runtimeWidth
        return min(max(storedOffset, minOffset), maxOffset)
    }

    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minNotchHeight), maxNotchHeight)
    }
}
