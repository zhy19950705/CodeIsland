import AppKit
import SwiftUI

@MainActor
final class DisplayModeCoordinator {
    private let appState: AppState
    private(set) var panelController: PanelWindowController?
    private var lastResolvedMode: DisplayMode?
    private var defaultsObserver: NSObjectProtocol?
    private var panelStateObserver: NSObjectProtocol?
    private var autoModePoller: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        StatusItemController.shared.bind(appState: appState)

        if panelController == nil {
            panelController = PanelWindowController(appState: appState)
        }

        if currentResolvedMode() != .menuBar {
            panelController?.showPanel()
        }

        applyCurrentMode(force: true)
        observeChanges()
    }

    func stop() {
        autoModePoller?.invalidate()
        autoModePoller = nil

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }

        if let panelStateObserver {
            NotificationCenter.default.removeObserver(panelStateObserver)
            self.panelStateObserver = nil
        }
    }

    func revealPrimaryInterface() {
        switch currentResolvedMode() {
        case .menuBar:
            StatusItemController.shared.showPopover()
        case .auto, .notch:
            panelController?.revealPanel()
        }
    }

    func togglePrimaryInterface() {
        switch currentResolvedMode() {
        case .menuBar:
            StatusItemController.shared.togglePopover()
        case .auto, .notch:
            toggleNotchSurface()
        }
    }

    private func observeChanges() {
        guard defaultsObserver == nil, panelStateObserver == nil else { return }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCurrentMode()
            }
        }

        panelStateObserver = NotificationCenter.default.addObserver(
            forName: .codeIslandPanelStateDidChange,
            object: appState,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncMenuBarPopoverState()
            }
        }

        configureAutoModePolling()
    }

    private func applyCurrentMode(force: Bool = false) {
        let resolvedMode = currentResolvedMode()
        guard force || resolvedMode != lastResolvedMode else {
            configureAutoModePolling()
            syncMenuBarPopoverState()
            return
        }

        lastResolvedMode = resolvedMode

        switch resolvedMode {
        case .menuBar:
            panelController?.hidePanel()
        case .auto, .notch:
            panelController?.showPanel()
        }

        StatusItemController.shared.syncVisibility(resolvedDisplayMode: resolvedMode)
        syncMenuBarPopoverState()
        configureAutoModePolling()
    }

    private func syncMenuBarPopoverState() {
        guard currentResolvedMode() == .menuBar else {
            StatusItemController.shared.closePopover()
            return
        }

        switch appState.surface {
        case .approvalCard, .questionCard, .completionCard:
            StatusItemController.shared.showPopover()
        case .collapsed, .sessionList:
            break
        }
    }

    private func configureAutoModePolling() {
        autoModePoller?.invalidate()
        autoModePoller = nil

        guard SettingsManager.shared.displayMode == .auto else { return }

        autoModePoller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyCurrentMode()
            }
        }
    }

    private func currentResolvedMode() -> DisplayMode {
        ScreenSelector.shared.refreshScreens()
        return Self.resolveMode(
            SettingsManager.shared.displayMode,
            hasPhysicalNotch: selectedScreenHasPhysicalNotch(),
            screenCount: ScreenSelector.shared.availableScreens.count
        )
    }

    private func selectedScreenHasPhysicalNotch() -> Bool {
        ScreenSelector.shared.refreshScreens()
        let screen = ScreenSelector.shared.selectedScreen ?? ScreenDetector.preferredScreen
        return ScreenDetector.screenHasNotch(screen)
    }

    private func toggleNotchSurface() {
        if appState.surface.isExpanded {
            withAnimation(NotchAnimation.close) {
                appState.surface = .collapsed
            }
        } else {
            withAnimation(NotchAnimation.open) {
                appState.surface = .sessionList
                appState.cancelCompletionQueue()
                if appState.activeSessionId == nil {
                    appState.activeSessionId = appState.preferredSessionId
                }
            }
        }
    }

    nonisolated static func resolveMode(
        _ mode: DisplayMode,
        hasPhysicalNotch: Bool,
        screenCount: Int
    ) -> DisplayMode {
        _ = screenCount

        guard mode == .auto else { return mode }
        return hasPhysicalNotch ? .notch : .menuBar
    }
}
