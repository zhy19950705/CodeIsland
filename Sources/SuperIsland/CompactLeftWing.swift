import SwiftUI
import AppKit
import SuperIslandCore

struct CompactLeftWing: View {
    var appState: AppState
    let expanded: Bool
    let mascotSize: CGFloat
    let hasNotch: Bool
    let showToolStatus: Bool
    @AppStorage(SettingsKey.sessionGroupingMode) private var groupingMode = SettingsDefaults.sessionGroupingMode

    private var displaySession: SessionSnapshot? {
        let sid = appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
        guard let sid else { return nil }
        return appState.sessions[sid]
    }
    private var displaySource: String { displaySession?.source ?? appState.primarySource }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var liveTool: String? { displaySession?.currentTool }
    @State private var toolLinger = ToolLingerState()

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                AppLogoView(size: 36, showBackground: false)
                if appState.sessions.count > 1 {
                    HStack(spacing: 1) {
                        ForEach([("all", "ALL"), ("project", "PRJ"), ("status", "STA"), ("cli", "CLI")], id: \.0) { tag, label in
                            let selected = groupingMode == tag
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { groupingMode = tag }
                            } label: {
                                PixelText(
                                    text: label,
                                    color: selected ? Color(red: 0.3, green: 0.85, blue: 0.4) : .white.opacity(0.3),
                                    pixelSize: 1.3
                                )
                                .frame(minWidth: 32, minHeight: 22)
                                .background(
                                    Rectangle().fill(selected ? .white.opacity(0.1) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Rectangle().fill(.white.opacity(0.05)))
                    .overlay(Rectangle().stroke(.white.opacity(0.1), lineWidth: 1))
                }
            } else {
                MascotView(source: displaySource, status: displayStatus, size: mascotSize)
                    .id(displaySource)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: displaySource)

                // On notch screens, show tool name only (no description, space is tight)
                if hasNotch, showToolStatus, let tool = toolLinger.shownTool {
                    Text(tool)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(toolStatusColor(tool))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
        }
        .padding(.leading, 6)
        .clipped()
        .onChange(of: liveTool) { _, newTool in
            toolLinger.update(liveTool: newTool)
        }
        .onChange(of: appState.rotatingSessionId) { _, _ in
            toolLinger.reset(to: liveTool)
        }
        .onDisappear {
            toolLinger.cancelPendingHide()
        }
    }
}

/// Right side: project name + session count (detailed) or just count (simple)
