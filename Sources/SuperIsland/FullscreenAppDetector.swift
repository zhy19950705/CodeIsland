import AppKit
import CoreGraphics

/// 检测当前是否有应用处于全屏模式
struct FullscreenAppDetector {
    /// 只把“几乎完全覆盖屏幕”的窗口认作全屏，避免普通最大化窗口把刘海面板误隐藏。
    static func isWindowEffectivelyFullscreen(
        windowFrame: CGRect,
        screenFrame: CGRect
    ) -> Bool {
        let visibleBounds = windowFrame.intersection(screenFrame)
        guard !visibleBounds.isNull else { return false }

        let widthRatio = visibleBounds.width / screenFrame.width
        let heightRatio = visibleBounds.height / screenFrame.height

        // 阈值收紧到接近整屏，避免把“放大但非全屏”的窗口误判成全屏。
        return widthRatio >= 0.995 && heightRatio >= 0.985
    }

    /// 检查指定屏幕上是否有前台应用处于全屏模式
    /// - Parameter screenFrame: 屏幕 frame
    /// - Returns: 是否有应用处于全屏模式
    static func isFullscreenAppActive(screenFrame: CGRect) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let currentAppBundleId = Bundle.main.bundleIdentifier
        if frontmostApp.bundleIdentifier == currentAppBundleId {
            return false
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontmostApp.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                continue
            }

            if isWindowEffectivelyFullscreen(windowFrame: bounds, screenFrame: screenFrame) {
                return true
            }
        }

        return false
    }
}
