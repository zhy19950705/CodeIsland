import Foundation

// Workspace jump data models and target metadata live here to keep the coordinator focused on dispatch.
extension WorkspaceJumpManager {
    struct CmuxTreeSnapshot: Decodable {
        var windows: [CmuxWindow]
    }

    struct CmuxWindow: Decodable {
        var workspaces: [CmuxWorkspace]
    }

    struct CmuxWorkspace: Decodable {
        var ref: String
        var panes: [CmuxPane]
    }

    struct CmuxPane: Decodable {
        var ref: String
        var surfaceRefs: [String]
        var selectedSurfaceRef: String?

        // The cmux CLI exports snake_case keys, so decoding keeps the integration compatible with the JSON payload.
        private enum CodingKeys: String, CodingKey {
            case ref
            case surfaceRefs = "surface_refs"
            case selectedSurfaceRef = "selected_surface_ref"
        }
    }

    enum JumpTarget {
        case cmux
        case ghostty
        case warp
        case iTerm
        case terminal
        case obsidian
        case codex
        case openCode
        case cursor
        case trae
        case qoder
        case codeBuddy
        case factory
        case windsurf
        case visualStudioCode
        case visualStudioCodeInsiders
        case vscodium
        case finder

        var title: String {
            switch self {
            case .cmux: return "cmux"
            case .ghostty: return "Ghostty"
            case .warp: return "Warp"
            case .iTerm: return "iTerm2"
            case .terminal: return "Terminal"
            case .obsidian: return "Obsidian"
            case .codex: return "Codex"
            case .openCode: return "OpenCode"
            case .cursor: return "Cursor"
            case .trae: return "Trae"
            case .qoder: return "Qoder"
            case .codeBuddy: return "CodeBuddy"
            case .factory: return "Factory"
            case .windsurf: return "Windsurf"
            case .visualStudioCode: return "VS Code"
            case .visualStudioCodeInsiders: return "VS Code Insiders"
            case .vscodium: return "VSCodium"
            case .finder: return "Finder"
            }
        }
    }

    struct ApplicationDescriptor {
        let bundleIdentifier: String
        let cliCandidates: [String]
        let uriScheme: String?
    }
}
