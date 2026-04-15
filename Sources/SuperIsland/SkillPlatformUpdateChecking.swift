import Foundation

// Remote update checks live here so the install and file-management code paths stay focused.
extension SkillManager {
    func refreshAvailableUpdates(for skills: [InstalledSkill]) async -> Bool {
        let candidates = skills.compactMap { skill -> (InstalledSkill, String)? in
            guard let reference = remoteCheckReference(for: skill.sourceMetadata) else { return nil }
            return (skill, reference)
        }
        guard !candidates.isEmpty else { return false }

        let references = Array(Set(candidates.map(\.1))).sorted()
        var remoteRevisions: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            for reference in references {
                group.addTask { [self] in
                    (reference, await remoteHeadRevision(for: reference))
                }
            }

            for await (reference, revision) in group {
                guard let revision else { continue }
                remoteRevisions[reference] = revision
            }
        }

        var didWrite = false
        for (skill, reference) in candidates {
            guard let remoteRevision = remoteRevisions[reference],
                  var metadata = skill.sourceMetadata,
                  metadata.cachedRemoteRevision != remoteRevision else {
                continue
            }

            metadata = SkillSourceMetadata(
                repoFullName: metadata.repoFullName,
                repoURL: metadata.repoURL,
                cloneURL: metadata.cloneURL,
                sourcePath: metadata.sourcePath,
                installedAt: metadata.installedAt,
                installedRevision: metadata.installedRevision,
                cachedRemoteRevision: remoteRevision
            )

            do {
                try writeSourceMetadata(metadata, to: skill.directoryURL)
                didWrite = true
            } catch {
                continue
            }
        }

        return didWrite
    }

    func remoteCheckReference(for metadata: SkillSourceMetadata?) -> String? {
        guard let metadata else { return nil }
        if let cloneURL = metadata.cloneURL?.nilIfEmpty {
            return cloneURL
        }
        return updateReference(for: metadata)
    }

    func currentRepositoryRevision(at repositoryURL: URL) throws -> String {
        // rev-parse is cheap and stable across Git versions, which keeps install-time metadata portable.
        try runGit(arguments: ["-C", repositoryURL.path, "rev-parse", "HEAD"])
    }

    func remoteHeadRevision(for reference: String) async -> String? {
        await Task.detached(priority: .utility) { [self] in
            guard let output = try? runGit(arguments: ["ls-remote", reference, "HEAD"]) else {
                return nil
            }
            return parseRemoteRevision(from: output)
        }.value
    }

    func parseRemoteRevision(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .first?
            .split(separator: "\t")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func runGit(arguments: [String]) throws -> String {
        guard fileManager.fileExists(atPath: "/usr/bin/git") else {
            throw SkillPlatformError.gitUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw SkillPlatformError.gitFailed(output.nilIfEmpty ?? "git command failed")
        }
        return output
    }
}
