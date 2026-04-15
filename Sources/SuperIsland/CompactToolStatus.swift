import SwiftUI
import AppKit
import SuperIslandCore

func toolStatusColor(_ tool: String) -> Color {
    switch tool.lowercased() {
    case "bash": return Color(red: 0.4, green: 1.0, blue: 0.5)
    case "edit", "write": return Color(red: 0.5, green: 0.7, blue: 1.0)
    case "read": return Color(red: 0.9, green: 0.8, blue: 0.4)
    case "grep", "glob": return Color(red: 0.8, green: 0.6, blue: 1.0)
    case "agent": return Color(red: 1.0, green: 0.6, blue: 0.4)
    default: return .white.opacity(0.7)
    }
}

// MARK: - Compact Tool Status (non-notch center area)

struct CompactToolStatus: View {
    var appState: AppState

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySession: SessionSnapshot? {
        guard let sid = displaySessionId else { return nil }
        return appState.sessions[sid]
    }
    private var liveTool: String? { displaySession?.currentTool }
    private var liveDesc: String? { displaySession?.toolDescription }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var projectName: String? {
        guard let cwd = displaySession?.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    @State private var toolLinger = ToolLingerState()
    @State private var shownDesc: String?

    private func shortDesc(_ desc: String) -> String {
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    private var hasActivity: Bool {
        toolLinger.shownTool != nil || displayStatus == .processing
    }

    var body: some View {
        HStack(spacing: 5) {
            if hasActivity, let project = projectName {
                Text(project)
                    .foregroundStyle(.white.opacity(0.8))
                    .id("center-project-\(displaySessionId ?? "")")
                    .transition(.opacity)
            }

            if let tool = toolLinger.shownTool {
                ProcessingSpinner(tint: toolStatusColor(tool), fontSize: 10.5)
                TypingIndicator(fontSize: 11, label: tool, bright: true, color: toolStatusColor(tool))
                    .id("tool-\(tool)-\(appState.rotatingSessionId ?? "")")
                if let desc = shownDesc {
                    Text(shortDesc(desc))
                        .foregroundStyle(.white.opacity(0.7))
                        .truncationMode(.tail)
                }
            } else if displayStatus == .processing {
                ProcessingSpinner(fontSize: 11)
                TypingIndicator(fontSize: 11, label: "thinking", bright: true)
                    .id("thinking-\(appState.rotatingSessionId ?? "")")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .padding(.leading, 6)
        .animation(.easeInOut(duration: 0.25), value: toolLinger.shownTool)
        .animation(.easeInOut(duration: 0.15), value: shownDesc)
        .animation(.easeInOut(duration: 0.3), value: appState.rotatingSessionId)
        .onChange(of: liveTool) { _, newTool in
            if newTool != nil {
                shownDesc = liveDesc
            }
            toolLinger.update(liveTool: newTool)
        }
        .onChange(of: liveDesc) { _, newDesc in
            if liveTool != nil { shownDesc = newDesc }
        }
        .onChange(of: toolLinger.shownTool) { _, shownTool in
            if shownTool == nil {
                shownDesc = nil
            }
        }
        .onChange(of: appState.rotatingSessionId) { _, _ in
            toolLinger.reset(to: liveTool)
            shownDesc = liveDesc
        }
        .onDisappear {
            toolLinger.cancelPendingHide()
        }
    }
}
