import Foundation

// Repository normalization and shallow clone logic are shared by every install path.
extension SkillManager {
    func normalizeRepositoryReference(
        _ reference: String,
        preferredSkillName: String? = nil
    ) throws -> NormalizedRepositoryReference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        if let url = URL(string: trimmed), let host = url.host, host.contains("github.com") {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 2 else {
                throw SkillPlatformError.invalidRepositoryReference
            }
            let owner = components[0]
            let repo = components[1].replacingOccurrences(of: ".git", with: "")
            guard let cloneURL = URL(string: "https://github.com/\(owner)/\(repo).git"),
                  let htmlURL = URL(string: "https://github.com/\(owner)/\(repo)") else {
                throw SkillPlatformError.invalidRepositoryReference
            }
            return NormalizedRepositoryReference(
                cloneURL: cloneURL,
                htmlURL: htmlURL,
                repoFullName: "\(owner)/\(repo)",
                repoName: repo,
                sourceRootPath: nil,
                preferredSkillName: preferredSkillName
            )
        }

        if let url = URL(string: trimmed), let host = url.host, host.contains("gitlab") {
            return try parseGitLabRepositoryReference(url: url, preferredSkillName: preferredSkillName)
        }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count == 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }
        let owner = components[0]
        let repo = components[1].replacingOccurrences(of: ".git", with: "")
        guard let cloneURL = URL(string: "https://github.com/\(owner)/\(repo).git"),
              let htmlURL = URL(string: "https://github.com/\(owner)/\(repo)") else {
            throw SkillPlatformError.invalidRepositoryReference
        }
        return NormalizedRepositoryReference(
            cloneURL: cloneURL,
            htmlURL: htmlURL,
            repoFullName: "\(owner)/\(repo)",
            repoName: repo,
            sourceRootPath: nil,
            preferredSkillName: preferredSkillName
        )
    }

    func parseGitLabRepositoryReference(
        url: URL,
        preferredSkillName: String?
    ) throws -> NormalizedRepositoryReference {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard components.count >= 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        let treeMarkerIndex = components.firstIndex(of: "-")
        let repositoryComponents = Array(components.prefix(treeMarkerIndex ?? components.count))
        guard repositoryComponents.count >= 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        let repoName = repositoryComponents.last!
        let repoFullName = repositoryComponents.joined(separator: "/")
        let baseURL = URL(string: "\(url.scheme ?? "http")://\(url.host ?? "")")!
        let repositoryPath = repositoryComponents.joined(separator: "/")
        guard let cloneURL = URL(string: "\(baseURL.absoluteString)/\(repositoryPath).git"),
              let htmlURL = URL(string: "\(baseURL.absoluteString)/\(repositoryPath)") else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        var sourceRootPath: String?
        if let treeMarkerIndex, components.count > treeMarkerIndex + 3 {
            sourceRootPath = components[(treeMarkerIndex + 3)...].joined(separator: "/")
        }

        return NormalizedRepositoryReference(
            cloneURL: cloneURL,
            htmlURL: htmlURL,
            repoFullName: repoFullName,
            repoName: repoName,
            sourceRootPath: sourceRootPath?.nilIfEmpty,
            preferredSkillName: preferredSkillName
        )
    }

    func cloneRepository(reference cloneURL: URL, to destination: URL) async throws {
        guard fileManager.fileExists(atPath: "/usr/bin/git") else {
            throw SkillPlatformError.gitUnavailable
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["clone", "--depth", "1", cloneURL.absoluteString, destination.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "git clone failed"
                throw SkillPlatformError.gitFailed(output)
            }
        }.value
    }
}
