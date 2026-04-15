import Foundation

// UpdateCheckerSupport holds pure helpers that are safe to test without touching AppKit or network state.
struct UpdateManifest: Decodable {
    let version: String
    let downloadUrl: String?
    let releaseURL: String?
    let publishedAt: String?
    let notes: String?

    // Normalize leading release prefixes once so callers compare and display the same version string.
    var normalizedVersion: String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    enum CodingKeys: String, CodingKey {
        case version
        case downloadUrl
        case releaseURL = "releaseUrl"
        case publishedAt
        case notes
    }
}

enum UpdateVersioning {
    static func isRemoteVersionNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue > localValue { return true }
            if remoteValue < localValue { return false }
        }
        return false
    }
}

enum UpdateInstallPaths {
    static func resolveInstallTargetPath(
        currentAppPath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> String {
        let currentURL = URL(fileURLWithPath: currentAppPath).standardizedFileURL
        let normalizedPath = currentURL.path
        let lowercasedPath = normalizedPath.lowercased()

        if lowercasedPath.contains("/apptranslocation/") || lowercasedPath.hasPrefix("/volumes/") {
            let appName = currentURL.lastPathComponent
            let candidates = [
                URL(fileURLWithPath: homeDirectoryPath)
                    .appendingPathComponent("Applications", isDirectory: true)
                    .appendingPathComponent(appName, isDirectory: true)
                    .path,
                URL(fileURLWithPath: "/Applications", isDirectory: true)
                    .appendingPathComponent(appName, isDirectory: true)
                    .path,
            ]

            if let existing = candidates.first(where: fileExists) {
                return existing
            }
            return candidates[0]
        }

        return normalizedPath
    }
}

enum UpdateShell {
    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum UpdateError: LocalizedError {
    case appNotFoundInDMG
    case downloadDidNotFinish

    var errorDescription: String? {
        switch self {
        case .appNotFoundInDMG:
            return "Could not find the app bundle in the downloaded disk image."
        case .downloadDidNotFinish:
            return "The update download finished without a disk image."
        }
    }
}
