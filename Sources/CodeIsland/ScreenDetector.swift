import AppKit

struct ScreenDetector {
    struct Candidate {
        let frame: CGRect
        let hasNotch: Bool
        let isMain: Bool
    }

    /// Simulated notch width for non-notch screens — scales with screen width
    private static func fakeNotchWidth(for screen: NSScreen) -> CGFloat {
        let screenW = screen.frame.width
        return min(max(screenW * 0.14, 160), 240)
    }

    static func resolvedNotchWidth(
        screenWidth: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?,
        override: CGFloat?
    ) -> CGFloat {
        if let override, override > 0 {
            return override
        }

        let leftWidth = auxiliaryLeftWidth ?? 0
        let rightWidth = auxiliaryRightWidth ?? 0
        if leftWidth > 0 || rightWidth > 0 {
            return screenWidth - leftWidth - rightWidth
        }

        return min(max(screenWidth * 0.14, 160), 240)
    }

    static func defaultManualNotchWidth(for screen: NSScreen? = NSScreen.main) -> Int {
        let targetScreen = screen ?? preferredScreen
        return Int(automaticNotchWidth(for: targetScreen).rounded())
    }

    static func autoPreferredIndex(candidates: [Candidate], activeWindowBounds: CGRect?) -> Int? {
        guard !candidates.isEmpty else { return nil }

        if let activeWindowBounds {
            let center = CGPoint(x: activeWindowBounds.midX, y: activeWindowBounds.midY)
            if let index = candidates.firstIndex(where: { $0.frame.contains(center) }) {
                return index
            }

            let bestOverlap = candidates.enumerated()
                .map { offset, candidate in
                    (offset, overlapArea(lhs: candidate.frame, rhs: activeWindowBounds))
                }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            if let bestOverlap, bestOverlap.1 > 0 {
                return bestOverlap.0
            }
        }

        if let notchIndex = candidates.firstIndex(where: \.hasNotch) {
            return notchIndex
        }

        if let mainIndex = candidates.firstIndex(where: \.isMain) {
            return mainIndex
        }

        return candidates.indices.first
    }

    /// Preferred screen: active work screen first, then built-in (notch), then main
    static var preferredScreen: NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main ?? NSScreen()
        }

        let mainScreen = NSScreen.main
        let candidates = screens.map { screen in
            Candidate(
                frame: screen.frame,
                hasNotch: screen.isBuiltinDisplay || screenHasNotch(screen),
                isMain: mainScreen == screen
            )
        }

        if let index = autoPreferredIndex(
            candidates: candidates,
            activeWindowBounds: activeScreenHintBounds()
        ), index < screens.count {
            return screens[index]
        }

        return mainScreen ?? screens.first ?? NSScreen()
    }

    static var hasNotch: Bool {
        screenHasNotch(preferredScreen)
    }

    /// Check if a specific screen has a notch
    static func screenHasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
        }
        return false
    }

    /// Height of the notch/menu bar area for a specific screen
    static func topBarHeight(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let real = screen.safeAreaInsets.top
            if real > 0 { return real }
        }
        // Menu bar height — only present on the screen that has it
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // On the primary screen, this is ~25pt (non-notch) or ~37pt (notch)
        // On secondary screens without menu bar, this is 0
        if menuBarHeight > 5 { return menuBarHeight }
        // Fallback: use main screen's menu bar height, or default 25
        if let main = NSScreen.main {
            let mainMenuBar = main.frame.maxY - main.visibleFrame.maxY
            if mainMenuBar > 5 { return mainMenuBar }
        }
        return 25
    }

    /// Height of the notch area — returns menu bar height on non-notch screens
    static var notchHeight: CGFloat {
        topBarHeight(for: preferredScreen)
    }

    /// Width of the notch — returns simulated width on non-notch screens
    static var notchWidth: CGFloat {
        notchWidth(for: preferredScreen)
    }

    /// Width of the notch for a specific screen
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if let override = notchWidthOverride() {
            return override
        }

        return automaticNotchWidth(for: screen)
    }

    private static func automaticNotchWidth(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            return resolvedNotchWidth(
                screenWidth: screen.frame.width,
                auxiliaryLeftWidth: leftWidth,
                auxiliaryRightWidth: rightWidth,
                override: nil
            )
        }
        return fakeNotchWidth(for: screen)
    }

    private static func notchWidthOverride() -> CGFloat? {
        let value = UserDefaults.standard.integer(forKey: SettingsKey.notchWidthOverride)
        guard value > 0 else { return nil }
        return CGFloat(value)
    }

    static func signature(for screen: NSScreen) -> String {
        let frame = screen.frame.integral
        return "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height))"
    }

    private static func overlapArea(lhs: CGRect, rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    /// Returns a tiny rect at the current pointer location to hint which
    /// screen the user is currently working on.
    ///
    /// Previously this method called `CGWindowListCopyWindowInfo` to locate the
    /// frontmost app's main window. On macOS 15+ that API triggers spurious
    /// "App X wants to record your screen" prompts for whichever app happens to
    /// be in the foreground (the caller polls it frequently). The mouse
    /// location is a zero-permission proxy that is good enough for picking the
    /// right display, and `autoPreferredIndex` only relies on the rect's
    /// midpoint / overlap when choosing a candidate screen.
    private static func activeScreenHintBounds() -> CGRect? {
        let location = NSEvent.mouseLocation
        return CGRect(x: location.x, y: location.y, width: 1, height: 1)
    }
}
