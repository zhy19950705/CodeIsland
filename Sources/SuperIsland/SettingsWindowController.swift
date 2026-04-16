import AppKit
import Combine
import SwiftUI

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private weak var appState: AppState?

    private var closeObserver: NSObjectProtocol?
    private var updateAccessoryController: NSTitlebarAccessoryViewController?
    private var updateStateCancellable: AnyCancellable?

    func bind(appState: AppState) {
        self.appState = appState
        observeUpdateStateIfNeeded()

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
        observeUpdateStateIfNeeded()

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
            refreshUpdateAccessory(on: window)
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
        window.title = AppText.shared["settings_title"]
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController
        window.contentMinSize = minSize
        window.setContentSize(NSSize(width: winW, height: winH))
        window.toolbar = nil
        refreshUpdateAccessory(on: window)
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

    private func observeUpdateStateIfNeeded() {
        guard updateStateCancellable == nil else { return }
        updateStateCancellable = UpdateChecker.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.refreshUpdateAccessory(on: window)
            }
    }

    private func refreshUpdateAccessory(on window: NSWindow) {
        let shouldShow = UpdateChecker.shared.availableUpdate != nil || UpdateChecker.shared.isDownloading

        if shouldShow {
            installUpdateAccessoryIfNeeded(on: window)
        } else if let updateAccessoryController {
            window.removeTitlebarAccessoryViewController(at: window.titlebarAccessoryViewControllers.firstIndex(of: updateAccessoryController) ?? 0)
            self.updateAccessoryController = nil
        }
    }

    private func installUpdateAccessoryIfNeeded(on window: NSWindow) {
        guard updateAccessoryController == nil else { return }

        let hostingView = NSHostingView(rootView: SettingsWindowUpdateAccessoryView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 144, height: 30)

        let controller = NSTitlebarAccessoryViewController()
        controller.view = hostingView
        controller.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(controller)
        updateAccessoryController = controller
    }

    static func bundleAppIcon() -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)
        return image
    }
}

private struct SettingsWindowUpdateAccessoryView: View {
    @ObservedObject private var l10n = AppText.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    private var isUpdateAvailable: Bool {
        updateChecker.availableUpdate != nil
    }

    private var title: String {
        if updateChecker.isDownloading {
            return l10n["update_downloading_short"]
        }
        if isUpdateAvailable {
            return l10n["update_badge"]
        }
        return l10n["check_for_updates_short"]
    }

    private var foregroundColor: Color {
        isUpdateAvailable || updateChecker.isDownloading ? .white : .secondary
    }

    private var backgroundColor: Color {
        if isUpdateAvailable || updateChecker.isDownloading {
            return Color.accentColor
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        Button {
            updateChecker.presentAvailableUpdateOrCheck()
        } label: {
            HStack(spacing: 6) {
                if updateChecker.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: isUpdateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(updateChecker.isDownloading)
        .help(isUpdateAvailable ? l10n["update_available_title"] : l10n["check_for_updates"])
    }
}
