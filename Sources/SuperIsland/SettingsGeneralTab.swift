import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - General Page

struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var screenSelector = ScreenSelector.shared
    @AppStorage(SettingsKey.allowHorizontalDrag) private var allowHorizontalDrag = SettingsDefaults.allowHorizontalDrag
    @AppStorage(SettingsKey.menuBarShowDetail) private var menuBarShowDetail = SettingsDefaults.menuBarShowDetail
    @State private var launchAtLogin: Bool
    @State private var displayMode: DisplayMode

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
        _displayMode = State(initialValue: SettingsManager.shared.displayMode)
    }

    var body: some View {
        Form {
            Section {
                Picker(l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Toggle(l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
                Toggle(l10n["allow_horizontal_drag"], isOn: $allowHorizontalDrag)
                    .onChange(of: allowHorizontalDrag) { _, enabled in
                        if !enabled {
                            SettingsManager.shared.panelHorizontalOffset = 0
                        }
                    }
                Text(l10n["allow_horizontal_drag_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(l10n["display_mode"], selection: $displayMode) {
                    Text(l10n["display_mode_auto"]).tag(DisplayMode.auto)
                    Text(l10n["display_mode_notch"]).tag(DisplayMode.notch)
                    Text(l10n["display_mode_menu_bar"]).tag(DisplayMode.menuBar)
                }
                .pickerStyle(.segmented)
                .onChange(of: displayMode) { _, newValue in
                    SettingsManager.shared.displayMode = newValue
                }
                if resolvedDisplayMode == .menuBar {
                    Toggle(l10n["menu_bar_show_detail"], isOn: $menuBarShowDetail)
                    Text(menuBarShortcutHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(l10n["display"], selection: displaySelection) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(screenSelector.availableScreens.enumerated()), id: \.offset) { index, screen in
                        Text(displayLabel(for: screen)).tag(screenOptionID(for: screen, index: index))
                    }
                }
            }

        }
        .formStyle(.grouped)
        .onAppear {
            screenSelector.refreshScreens()
        }
    }

    private var displaySelection: Binding<String> {
        Binding(
            get: {
                switch screenSelector.selectionMode {
                case .automatic:
                    return "auto"
                case .specificScreen:
                    guard let selectedScreen = screenSelector.selectedScreen,
                          let match = Array(screenSelector.availableScreens.enumerated()).first(where: {
                              screenSelector.isSelected($0.element)
                          }) else {
                        return "auto"
                    }
                    return screenOptionID(for: selectedScreen, index: match.offset)
                }
            },
            set: { selection in
                if selection == "auto" {
                    screenSelector.selectAutomatic()
                    return
                }

                guard let match = Array(screenSelector.availableScreens.enumerated()).first(where: {
                    screenOptionID(for: $0.element, index: $0.offset) == selection
                }) else {
                    screenSelector.selectAutomatic()
                    return
                }

                screenSelector.selectScreen(match.element)
            }
        )
    }

    private var resolvedDisplayMode: DisplayMode {
        let screen = screenSelector.selectedScreen ?? ScreenDetector.preferredScreen
        return DisplayModeCoordinator.resolveMode(
            displayMode,
            hasPhysicalNotch: ScreenDetector.screenHasNotch(screen),
            screenCount: max(screenSelector.availableScreens.count, 1)
        )
    }

    private var menuBarShortcutHint: String {
        let shortcut = ShortcutAction.togglePanel.defaultBinding?.displayString ?? "⌘⇧I"
        return "\(l10n["menu_bar_shortcut_hint_prefix"]) \(shortcut). \(l10n["menu_bar_shortcut_hint_suffix"])"
    }

    private func displayLabel(for screen: NSScreen) -> String {
        let baseLabel = screen.isBuiltinDisplay ? l10n["builtin_display"] : screen.localizedName
        var suffixes: [String] = []

        if screen == NSScreen.main {
            suffixes.append(l10n["main_display"])
        }
        if ScreenDetector.screenHasNotch(screen) {
            suffixes.append(l10n["notch"])
        }

        guard !suffixes.isEmpty else { return baseLabel }
        return ([baseLabel] + suffixes).joined(separator: " ")
    }

    private func screenOptionID(for screen: NSScreen, index: Int) -> String {
        if let displayID = screen.displayID {
            return "screen-\(displayID)"
        }
        return "screen-\(screen.localizedName)-\(index)"
    }
}
