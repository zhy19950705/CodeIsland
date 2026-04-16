import SwiftUI

struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    let hasNotch: Bool
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                // Reuse the shared notch controls so every surface keeps the same spacing and hover behavior.
                NotchControlButtonGroup(showsSoundToggle: true, trailingAction: .quitApp)
            } else {
                if appState.status == .waitingApproval || appState.status == .waitingQuestion {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                        .symbolEffect(.pulse, options: .repeating)
                }

                // Keep the compact right wing focused on session presence once top-level usage badges are hidden.
                HStack(spacing: 1) {
                    let active = appState.activeSessionCount
                    let total = appState.totalSessionCount
                    if active > 0 {
                        Text("\(active)")
                            .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.5))
                        Text("/")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text("\(total)")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .font(.system(size: showToolStatus ? 12 : 13, weight: showToolStatus ? .semibold : .bold, design: .monospaced))
            }
        }
        .padding(.trailing, 6)
    }
}

// MARK: - Tool Status Helpers
