import AppKit
import Foundation

extension SkillManager {
    func ensureSharedRootExists() throws {
        try fileManager.createDirectory(at: sharedRootURL, withIntermediateDirectories: true)
    }

    func openSharedRoot() {
        try? ensureSharedRootExists()
        workspace.open(sharedRootURL)
    }

    func reveal(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }

    func discoverSkills() throws -> [InstalledSkill] {
        try ensureSharedRootExists()
        var discovered: [InstalledSkill] = []
        var seenResolvedDirectories = Set<String>()

        for storageRoot in skillStorageRoots() {
            let entries = (try? fileManager.contentsOfDirectory(
                at: storageRoot.rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let resolvedPath = entry.resolvingSymlinksInPath().standardizedFileURL.path
                guard !seenResolvedDirectories.contains(resolvedPath) else { continue }
                guard let skill = loadSkill(
                    from: entry,
                    storageKind: storageRoot.kind,
                    isAdoptableToSharedLibrary: isGlobalSkillRoot(storageRoot.rootURL)
                ) else { continue }
                seenResolvedDirectories.insert(resolvedPath)
                discovered.append(skill)
            }
        }

        return discovered.sorted { lhs, rhs in
            if lhs.isSharedLibrarySkill != rhs.isSharedLibrarySkill {
                return lhs.isSharedLibrarySkill && !rhs.isSharedLibrarySkill
            }
            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.directoryURL.path < rhs.directoryURL.path
        }
    }

    func importSkillToSharedLibrary(_ skill: InstalledSkill) throws -> InstalledSkill {
        try ensureSharedRootExists()
        guard skill.isAdoptableToSharedLibrary else {
            throw SkillPlatformError.projectScopedSkillCannotBeImported
        }
        return try installSkillDirectory(
            from: skill.directoryURL,
            preferredFolderName: skill.folderName,
            metadata: skill.sourceMetadata
        )
    }

    func importSkillsToSharedLibrary(_ skills: [InstalledSkill]) throws -> SkillAdoptionSummary {
        try ensureSharedRootExists()

        var imported: [InstalledSkill] = []
        var skipped: [InstalledSkill] = []

        for skill in skills where !skill.isSharedLibrarySkill {
            guard skill.isAdoptableToSharedLibrary else {
                skipped.append(skill)
                continue
            }
            do {
                imported.append(try importSkillToSharedLibrary(skill))
            } catch SkillPlatformError.skillAlreadyExists {
                skipped.append(skill)
            }
        }

        return SkillAdoptionSummary(imported: imported, skipped: skipped)
    }

    func agentSnapshots() -> [SkillAgentLinkSnapshot] {
        SkillAgentID.allCases.map(snapshot(for:))
    }

    func linkAllAgents() throws {
        for agent in SkillAgentID.allCases where agent != .codex {
            let snapshot = snapshot(for: agent)
            if snapshot.state == .missing {
                try link(agent)
            }
        }
    }

    func repairGlobalAgentLinks() -> SkillLinkRepairSummary {
        var linkedAgents: [SkillAgentID] = []
        var conflictAgents: [SkillAgentID] = []

        for agent in SkillAgentID.allCases where agent != .codex {
            let state = snapshot(for: agent).state
            switch state {
            case .missing:
                do {
                    try link(agent)
                    linkedAgents.append(agent)
                } catch {
                    conflictAgents.append(agent)
                }
            case .conflict:
                conflictAgents.append(agent)
            case .native, .linked:
                break
            }
        }

        return SkillLinkRepairSummary(
            linkedAgents: linkedAgents,
            conflictAgents: conflictAgents
        )
    }

    func resolveConflict(for agent: SkillAgentID) throws -> SkillConflictResolutionSummary {
        try ensureSharedRootExists()

        let snapshot = snapshot(for: agent)
        guard snapshot.state == .conflict else {
            throw SkillPlatformError.linkConflict(displayPath(snapshot.skillsURL))
        }

        let skillsToImport = discoverSkills(in: snapshot.skillsURL, storageKind: .agent(agent), isAdoptableToSharedLibrary: true)
        let adoption = try importSkillsToSharedLibrary(skillsToImport)
        try fileManager.removeItem(at: snapshot.skillsURL)
        try link(agent)

        return SkillConflictResolutionSummary(
            agent: agent,
            adoption: adoption
        )
    }

    func resolveAllConflicts() throws -> SkillBulkConflictResolutionSummary {
        let resolutions = try agentSnapshots()
            .filter { $0.state == .conflict }
            .map { try resolveConflict(for: $0.agent) }
        return SkillBulkConflictResolutionSummary(resolutions: resolutions)
    }

    func link(_ agent: SkillAgentID) throws {
        try ensureSharedRootExists()
        let destination = agent.skillsURL(homeDirectory: homeDirectory)
        if destination.standardizedFileURL == sharedRootURL.standardizedFileURL { return }

        if fileManager.fileExists(atPath: destination.path) || isDanglingSymlink(destination) {
            let snapshot = snapshot(for: agent)
            switch snapshot.state {
            case .linked:
                return
            case .missing:
                break
            case .native, .conflict:
                throw SkillPlatformError.linkConflict(displayPath(destination))
            }
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: sharedRootURL)
    }

    func unlink(_ agent: SkillAgentID) throws {
        let destination = agent.skillsURL(homeDirectory: homeDirectory)
        if destination.standardizedFileURL == sharedRootURL.standardizedFileURL { return }

        let snapshot = snapshot(for: agent)
        guard snapshot.state == .linked else { return }
        try fileManager.removeItem(at: destination)
    }

    func importSkills(from sourceRoot: URL) throws -> [InstalledSkill] {
        try ensureSharedRootExists()
        let skillDirectories = try discoverSkillDirectories(in: sourceRoot)
        guard !skillDirectories.isEmpty else {
            throw SkillPlatformError.noSkillsFound
        }

        return try skillDirectories.map { sourceDirectory in
            try installSkillDirectory(
                from: sourceDirectory,
                preferredFolderName: sourceDirectory.lastPathComponent,
                metadata: nil
            )
        }
    }

    func displayPath(_ url: URL) -> String {
        let path = url.path
        let homePath = homeDirectory.path
        guard path.hasPrefix(homePath) else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    func previewDocument(for skill: InstalledSkill) throws -> SkillPreviewDocument {
        let skillURL = skill.directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        let contents = try String(contentsOf: skillURL, encoding: .utf8)
        return SkillPreviewDocument(
            id: "skill:\(skill.id)",
            title: skill.name,
            subtitle: displayPath(skillURL),
            body: contents,
            bodyHTML: nil,
            sourceURL: skill.sourceMetadata?.repoURL.flatMap(URL.init(string:)),
            metadata: [
                skill.version.map { "Version \($0)" },
                skill.author.map { "Author \($0)" },
                skill.sourceMetadata?.repoFullName.map { "Source \($0)" },
                "Storage \(storageLabel(for: skill.storageKind))",
            ].compactMap { $0 }
        )
    }

    func storageLabel(for kind: SkillStorageKind) -> String {
        switch kind {
        case .shared:
            return "Shared"
        case .legacyAgent:
            return "Legacy .agent"
        case .agent(let agent):
            return agent.title
        }
    }

    func skillStorageRoots() -> [SkillStorageRoot] {
        var roots: [SkillStorageRoot] = [
            SkillStorageRoot(kind: .shared, rootURL: sharedRootURL)
        ]

        let legacyRoot = legacyAgentRootURL
        if fileManager.fileExists(atPath: legacyRoot.path), !resolves(toSharedRoot: legacyRoot) {
            roots.append(SkillStorageRoot(kind: .legacyAgent, rootURL: legacyRoot))
        }

        for agent in SkillAgentID.allCases where agent != .codex {
            let root = agent.skillsURL(homeDirectory: homeDirectory)
            guard fileManager.fileExists(atPath: root.path) || isDanglingSymlink(root) else { continue }
            guard !resolves(toSharedRoot: root) else { continue }
            guard root.standardizedFileURL != legacyRoot.standardizedFileURL else { continue }
            roots.append(SkillStorageRoot(kind: .agent(agent), rootURL: root))
        }

        return roots
    }

    func resolves(toSharedRoot url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL == sharedRootURL.standardizedFileURL
    }

    func isGlobalSkillRoot(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        if normalized == sharedRootURL.standardizedFileURL { return false }
        if normalized == legacyAgentRootURL.standardizedFileURL { return true }
        return SkillAgentID.allCases
            .filter { $0 != .codex }
            .map { $0.skillsURL(homeDirectory: homeDirectory).standardizedFileURL }
            .contains(normalized)
    }

    func snapshot(for agent: SkillAgentID) -> SkillAgentLinkSnapshot {
        let path = agent.skillsURL(homeDirectory: homeDirectory)
        if path.standardizedFileURL == sharedRootURL.standardizedFileURL {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .native,
                detail: "直接使用共享技能库"
            )
        }

        guard fileManager.fileExists(atPath: path.path) || isDanglingSymlink(path) else {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .missing,
                detail: "尚未链接"
            )
        }

        do {
            let values = try path.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: path.path)
                let resolvedURL = URL(fileURLWithPath: destination, relativeTo: path.deletingLastPathComponent())
                    .standardizedFileURL
                if resolvedURL == sharedRootURL.standardizedFileURL {
                    return SkillAgentLinkSnapshot(
                        agent: agent,
                        skillsURL: path,
                        state: .linked,
                        detail: "已链接到 \(displayPath(sharedRootURL))"
                    )
                }
            }
        } catch {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .conflict,
                detail: error.localizedDescription
            )
        }

        return SkillAgentLinkSnapshot(
            agent: agent,
            skillsURL: path,
            state: .conflict,
            detail: "目录已存在，但没有链接到共享技能库"
        )
    }

    func loadSkill(
        from directoryURL: URL,
        storageKind: SkillStorageKind,
        isAdoptableToSharedLibrary: Bool
    ) -> InstalledSkill? {
        let skillFileURL = directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        guard fileManager.fileExists(atPath: skillFileURL.path) else { return nil }
        let contents = (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
        let metadata = extractSkillMetadata(from: contents, fallbackName: directoryURL.lastPathComponent)
        let resourceValues = try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey])
        return InstalledSkill(
            directoryURL: directoryURL,
            name: metadata.name,
            description: metadata.description,
            version: metadata.version,
            author: metadata.author,
            modifiedAt: resourceValues?.contentModificationDate,
            sourceMetadata: loadSourceMetadata(from: directoryURL),
            storageKind: storageKind,
            isAdoptableToSharedLibrary: isAdoptableToSharedLibrary
        )
    }

    func discoverSkills(
        in rootURL: URL,
        storageKind: SkillStorageKind,
        isAdoptableToSharedLibrary: Bool
    ) -> [InstalledSkill] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return loadSkill(
                from: entry,
                storageKind: storageKind,
                isAdoptableToSharedLibrary: isAdoptableToSharedLibrary
            )
        }
    }

    func discoverSkillDirectories(in sourceRoot: URL, preferredSkillName: String? = nil) throws -> [URL] {
        var discovered = Set<URL>()
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            return []
        }

        let ignoredDirectoryNames = Set([".git", "node_modules", "dist", "build", ".next"])

        for case let url as URL in enumerator {
            if ignoredDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "SKILL.md" else { continue }
            discovered.insert(url.deletingLastPathComponent().standardizedFileURL)
        }

        let all = Array(discovered).sorted { $0.path < $1.path }
        let accepted = all.filter { candidate in
            let relative = relativePathComponents(from: sourceRoot, to: candidate)
            if relative.isEmpty {
                return all.count == 1
            }
            if relative.count == 1 {
                return true
            }
            return relative.contains("skills")
        }

        if accepted.isEmpty,
           fileManager.fileExists(atPath: sourceRoot.appendingPathComponent("SKILL.md", isDirectory: false).path) {
            let rootOnly = [sourceRoot]
            return filterSkillDirectories(rootOnly, preferredSkillName: preferredSkillName)
        }
        return filterSkillDirectories(accepted, preferredSkillName: preferredSkillName)
    }

    func installSkillDirectory(
        from sourceDirectory: URL,
        preferredFolderName: String,
        metadata: SkillSourceMetadata?
    ) throws -> InstalledSkill {
        let skillFileURL = sourceDirectory.appendingPathComponent("SKILL.md", isDirectory: false)
        guard fileManager.fileExists(atPath: skillFileURL.path) else {
            throw SkillPlatformError.invalidSkillFolder(sourceDirectory)
        }

        let destinationURL = sharedRootURL.appendingPathComponent(preferredFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let existingMetadata = loadSourceMetadata(from: destinationURL),
               let metadata,
               existingMetadata.repoFullName == metadata.repoFullName,
               existingMetadata.sourcePath == metadata.sourcePath {
                try fileManager.removeItem(at: destinationURL)
            } else {
                throw SkillPlatformError.skillAlreadyExists(preferredFolderName)
            }
        }

        let temporaryURL = sharedRootURL.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try copyDirectoryRecursively(from: sourceDirectory, to: temporaryURL)
        if let metadata {
            try writeSourceMetadata(metadata, to: temporaryURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        guard let installedSkill = loadSkill(
            from: destinationURL,
            storageKind: .shared,
            isAdoptableToSharedLibrary: false
        ) else {
            throw SkillPlatformError.invalidSkillFolder(destinationURL)
        }
        return installedSkill
    }

    func filterSkillDirectories(_ directories: [URL], preferredSkillName: String?) -> [URL] {
        guard let preferredSkillName, !preferredSkillName.isEmpty else {
            return directories
        }

        let exactMatches = directories.filter { directory in
            if directory.lastPathComponent == preferredSkillName {
                return true
            }
            let skillFileURL = directory.appendingPathComponent("SKILL.md", isDirectory: false)
            guard let contents = try? String(contentsOf: skillFileURL, encoding: .utf8) else {
                return false
            }
            let metadata = extractSkillMetadata(from: contents, fallbackName: directory.lastPathComponent)
            return metadata.name == preferredSkillName
        }
        return exactMatches
    }

    func extractSkillMetadata(from contents: String, fallbackName: String) -> SkillManifestMetadata {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var frontmatterLines: [String] = []
        var bodyLines = lines
        if lines.first == "---",
           let closingIndex = lines.dropFirst().firstIndex(of: "---") {
            frontmatterLines = Array(lines[1..<closingIndex])
            bodyLines = Array(lines[(closingIndex + 1)...])
        }

        let frontmatter = Dictionary(uniqueKeysWithValues: frontmatterLines.compactMap { line -> (String, String)? in
            guard let colonIndex = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : (key.lowercased(), value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        })

        let heading = bodyLines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        let summary = bodyLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("- ") && !line.hasPrefix("* ")
            }

        let rawName = frontmatter["name"] ?? heading ?? fallbackName
        let rawDescription = frontmatter["description"] ?? summary ?? "No description"
        let rawVersion = normalizedFrontmatterValue(frontmatter["version"])
        let rawAuthor = normalizedFrontmatterValue(frontmatter["author"])

        return SkillManifestMetadata(
            name: rawName,
            description: rawDescription,
            version: rawVersion,
            author: rawAuthor
        )
    }

    func normalizedFrontmatterValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func loadSourceMetadata(from directoryURL: URL) -> SkillSourceMetadata? {
        let metadataURL = directoryURL.appendingPathComponent(Self.sourceMetadataFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SkillSourceMetadata.self, from: data)
    }

    func writeSourceMetadata(_ metadata: SkillSourceMetadata, to directoryURL: URL) throws {
        let metadataURL = directoryURL.appendingPathComponent(Self.sourceMetadataFileName, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    func copyDirectoryRecursively(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        while let url = enumerator?.nextObject() as? URL {
            let relative = relativePath(from: source, to: url)
            if relative == ".git" || relative.hasPrefix(".git/") {
                enumerator?.skipDescendants()
                continue
            }

            let targetURL = destination.appendingPathComponent(relative, isDirectory: false)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            if values.isDirectory == true {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else if values.isSymbolicLink == true {
                let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                try fileManager.createSymbolicLink(atPath: targetURL.path, withDestinationPath: linkDestination)
            } else {
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: url, to: targetURL)
            }
        }
    }

    func updateReference(for metadata: SkillSourceMetadata?) -> String? {
        guard let metadata else { return nil }
        if let repoURL = metadata.repoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !repoURL.isEmpty {
            return repoURL
        }
        if let repoFullName = metadata.repoFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !repoFullName.isEmpty {
            return repoFullName
        }
        return nil
    }

    func relativePath(from base: URL, to target: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath == basePath {
            return "."
        }
        return String(targetPath.dropFirst(basePath.count + 1))
    }

    func relativePathComponents(from base: URL, to target: URL) -> [String] {
        let relative = relativePath(from: base, to: target)
        if relative == "." {
            return []
        }
        return relative.split(separator: "/").map(String.init)
    }

    func isDanglingSymlink(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false)
    }
}
