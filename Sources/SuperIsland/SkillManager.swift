import AppKit
import Foundation

// SkillManager is the non-UI service root for skill discovery, install, and file operations.
// The service keeps immutable collaborators, so background read-only discovery can safely reuse the same instance.
final class SkillManager: @unchecked Sendable {
    static let sourceMetadataFileName = ".superisland-skill-source.json"
    // Mayidata currently exposes the skill hub over HTTP, so Info.plist keeps a host-scoped ATS exception for this URL.
    static let mayidataSkillHubURL = URL(string: "http://skillshub.mayidata.com")!
    let fileManager: FileManager
    let workspace: NSWorkspace
    let session: URLSession
    let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared,
        session: URLSession = .shared,
        homeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        self.session = session
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    var sharedRootURL: URL {
        SkillAgentID.codex.skillsURL(homeDirectory: homeDirectory)
    }

    var legacyAgentRootURL: URL {
        homeDirectory
            .appendingPathComponent(".agent", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }
}
