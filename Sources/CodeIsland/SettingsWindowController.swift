import AppKit
import SwiftUI

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private weak var appState: AppState?

    private var closeObserver: NSObjectProtocol?

    func bind(appState: AppState) {
        self.appState = appState

        if let hostingController = window?.contentViewController as? NSHostingController<SettingsView> {
            hostingController.rootView = SettingsView(appState: appState)
        }
    }

    func show() {
        // Switch to regular activation policy so the window can receive focus
        NSApp.setActivationPolicy(.regular)
        // Use the actual bundle app icon so Dock matches the packaged asset catalog icon.
        NSApp.applicationIconImage = Self.bundleAppIcon()

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenW = screen?.frame.width ?? 1440
        let screenH = screen?.frame.height ?? 900
        let winW = min(840, screenW * 0.85)
        let winH = min(700, screenH * 0.78)
        let minSize = NSSize(width: min(720, screenW * 0.55), height: min(540, screenH * 0.55))

        if let window = window {
            window.contentMinSize = minSize
            if window.frame.width < minSize.width || window.frame.height < minSize.height {
                let targetSize = NSSize(width: max(winW, minSize.width), height: max(winH, minSize.height))
                window.setContentSize(targetSize)
                window.center()
            }
            if let hostingController = window.contentViewController as? NSHostingController<SettingsView> {
                hostingController.rootView = SettingsView(appState: appState)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appState: appState)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.title = L10n.shared["settings_title"]
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController
        window.contentMinSize = minSize
        window.setContentSize(NSSize(width: winW, height: winH))
        window.toolbar = nil
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Revert to accessory policy when settings window is closed
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.accessory)
            NSApp.hide(nil)
        }

        self.window = window
    }

    static func bundleAppIcon() -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)
        return image
    }
}
