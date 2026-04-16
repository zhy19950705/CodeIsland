import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case ai
    case skills
    case behavior
    case appearance
    case mascots
    case sound
    case shortcuts
    case testing
    case hooks
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .ai: return "sparkles"
        case .skills: return "shippingbox.fill"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "paintbrush.fill"
        case .mascots: return "person.2.fill"
        case .sound: return "speaker.wave.2.fill"
        case .shortcuts: return "command.circle.fill"
        case .testing: return "testtube.2"
        case .hooks: return "link.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .ai: return .mint
        case .skills: return .teal
        case .behavior: return .orange
        case .appearance: return .blue
        case .mascots: return .pink
        case .sound: return .green
        case .shortcuts: return .indigo
        case .testing: return .orange
        case .hooks: return .purple
        case .about: return .cyan
        }
    }
}

private struct SidebarGroup: Hashable {
    let title: String?
    let pages: [SettingsPage]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: nil, pages: [.general, .ai, .skills, .behavior, .appearance, .mascots, .sound, .shortcuts]),
    SidebarGroup(title: "SuperIsland", pages: [.testing, .hooks, .about]),
]

// MARK: - Main View

struct SettingsView: View {
    @ObservedObject private var l10n = AppText.shared
    let appState: AppState?
    @State private var selectedPage: SettingsPage = .general
    @State private var skillPlatformViewModel = SkillPlatformViewModel()

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.pages) { page in
                            NavigationLink(value: page) {
                                SidebarRow(page: page)
                            }
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 240)

        } detail: {
            ZStack(alignment: .topLeading) {
                switch selectedPage {
                case .general: GeneralPage()
                case .ai: AIPage()
                // Keep the skills page model alive across page switches so local discovery does not restart each time.
                case .skills: SkillsPage(viewModel: skillPlatformViewModel)
                case .behavior: BehaviorPage()
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .shortcuts: ShortcutsPage()
                case .testing: TestingPage(appState: appState)
                case .hooks: HooksPage(appState: appState)
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarRow: View {
    @ObservedObject private var l10n = AppText.shared
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text(l10n[page.rawValue])
                .font(.system(size: 13))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
