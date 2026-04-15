import SwiftUI
import AppKit

struct NotchTrailingAction {
    let icon: String
    let tint: Color
    let tooltipKey: String
    let action: () -> Void

    // Keep the destructive close treatment identical to the notch quit button so both surfaces read as one system.
    static let closePopover = NotchTrailingAction(
        icon: "xmark",
        tint: Color(red: 1.0, green: 0.4, blue: 0.4),
        tooltipKey: "close",
        action: {
            // Hop back onto the main actor because the status item controller is UI-bound.
            Task { @MainActor in
                StatusItemController.shared.closePopover()
            }
        }
    )

    // Preserve the original notch behavior for the expanded island controls.
    static let quitApp = NotchTrailingAction(
        icon: "power",
        tint: Color(red: 1.0, green: 0.4, blue: 0.4),
        tooltipKey: "quit",
        action: { NSApplication.shared.terminate(nil) }
    )
}

struct NotchControlButtonGroup: View {
    let showsSoundToggle: Bool
    let trailingAction: NotchTrailingAction

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 4) {
            if showsSoundToggle {
                NotchIconButton(
                    icon: soundEnabled ? "speaker.wave.2" : "speaker.slash",
                    tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]
                ) {
                    soundEnabled.toggle()
                }
            }

            NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                SettingsWindowController.shared.show()
            }

            NotchIconButton(
                icon: trailingAction.icon,
                tint: trailingAction.tint,
                tooltip: l10n[trailingAction.tooltipKey],
                action: trailingAction.action
            )
        }
    }
}
