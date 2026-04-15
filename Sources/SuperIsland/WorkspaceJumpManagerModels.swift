import Foundation

// Workspace jump data models and target metadata live here to keep the coordinator focused on dispatch.
extension WorkspaceJumpManager {
    struct CmuxTreeSnapshot: Decodable {
        // RPC snapshots may include the active/caller cursor; CLI `tree --json` omits them, so keep both optional.
        var active: CmuxCursor?
        var caller: CmuxCursor?
        var windows: [CmuxWindow]
    }

    struct CmuxCursor: Decodable {
        var workspaceRef: String?
        var workspaceId: String?
        var paneRef: String?
        var paneId: String?
        var surfaceRef: String?
        var surfaceId: String?

        // RPC payloads are snake_case, so decoding keeps the model aligned with cmux output.
        private enum CodingKeys: String, CodingKey {
            case workspaceRef = "workspace_ref"
            case workspaceId = "workspace_id"
            case paneRef = "pane_ref"
            case paneId = "pane_id"
            case surfaceRef = "surface_ref"
            case surfaceId = "surface_id"
        }
    }

    struct CmuxWindow: Decodable {
        var id: String?
        var ref: String?
        var workspaces: [CmuxWorkspace]
    }

    struct CmuxWorkspace: Decodable {
        var id: String?
        var ref: String
        var panes: [CmuxPane]
    }

    struct CmuxPane: Decodable {
        var id: String?
        var ref: String
        var surfaceRefs: [String]
        var selectedSurfaceRef: String?
        var selectedSurfaceId: String?
        var surfaces: [CmuxSurface]?

        // The cmux CLI exports snake_case keys, so decoding keeps the integration compatible with the JSON payload.
        private enum CodingKeys: String, CodingKey {
            case id
            case ref
            case surfaceRefs = "surface_refs"
            case selectedSurfaceRef = "selected_surface_ref"
            case selectedSurfaceId = "selected_surface_id"
            case surfaces
        }
    }

    struct CmuxSurface: Decodable {
        var id: String?
        var ref: String
    }

    struct CmuxFocusTarget {
        var workspaceReference: String?
        var workspaceIdentifier: String?
        var paneReference: String?
        var paneIdentifier: String?
        var surfaceReference: String?
        var surfaceIdentifier: String?

        // Jump routing only needs to know whether there is at least one concrete cmux anchor to target.
        var isEmpty: Bool {
            workspaceReference == nil
                && workspaceIdentifier == nil
                && paneReference == nil
                && paneIdentifier == nil
                && surfaceReference == nil
                && surfaceIdentifier == nil
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
