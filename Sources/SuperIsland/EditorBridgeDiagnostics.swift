import AppKit
import Foundation

// Editor bridge diagnostics stay isolated from CLI diagnostics because they inspect app bundles and extension installs.
enum EditorBridgeHost: String, CaseIterable, Identifiable, Sendable {
    case visualStudioCode
    case cursor
    case windsurf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visualStudioCode: return "VS Code"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        }
    }

    var systemName: String {
        switch self {
        case .visualStudioCode: return "square.and.pencil"
        case .cursor: return "cursorarrow.rays"
        case .windsurf: return "wind"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .visualStudioCode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .windsurf: return "com.exafunction.windsurf"
        }
    }

    var extensionHost: IDEExtensionHost {
        switch self {
        case .visualStudioCode: return .visualStudioCode
        case .cursor: return .cursor
        case .windsurf: return .windsurf
        }
    }
}

enum EditorBridgeState: Sendable {
    case live
    case installed
    case unavailable

    var titleKey: String {
        switch self {
        case .live: return "editor_bridge_live"
        case .installed: return "editor_bridge_installed"
        case .unavailable: return "editor_bridge_unavailable"
        }
    }

    var detailKey: String {
        switch self {
        case .live: return "editor_bridge_live_detail"
        case .installed: return "editor_bridge_installed_detail"
        case .unavailable: return "editor_bridge_unavailable_detail"
        }
    }
}

struct EditorBridgeSnapshot: Identifiable, Sendable {
    var id: EditorBridgeHost { host }
    var host: EditorBridgeHost
    var state: EditorBridgeState
    var installPath: String?
    var extensionInstalled: Bool
}

final class EditorBridgeManager {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func snapshots() -> [EditorBridgeSnapshot] {
        EditorBridgeHost.allCases.map { host in
            let appURL = workspace.urlForApplication(withBundleIdentifier: host.bundleIdentifier)
            let isRunning = workspace.runningApplications.contains { application in
                application.bundleIdentifier == host.bundleIdentifier && !application.isTerminated
            }

            let state: EditorBridgeState
            if isRunning {
                state = .live
            } else if appURL != nil {
                state = .installed
            } else {
                state = .unavailable
            }

            return EditorBridgeSnapshot(
                host: host,
                state: state,
                installPath: appURL?.path,
                extensionInstalled: IDEExtensionInstaller.isInstalled(host.extensionHost)
            )
        }
    }

    func openInstallLocation(for host: EditorBridgeHost) {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: host.bundleIdentifier) else { return }
        workspace.open(appURL)
    }
}
