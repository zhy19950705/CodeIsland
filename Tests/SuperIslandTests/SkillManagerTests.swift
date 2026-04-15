import XCTest
@testable import SuperIsland

final class SkillManagerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var homeDirectory: URL!
    private var manager: SkillManager!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillManagerTests-\(UUID().uuidString)", isDirectory: true)
        homeDirectory = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        manager = SkillManager(homeDirectory: homeDirectory)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testDiscoverSkillsLoadsSharedLibraryEntries() throws {
        let root = manager.sharedRootURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let releaseNotes = root.appendingPathComponent("release-notes", isDirectory: true)
        try FileManager.default.createDirectory(at: releaseNotes, withIntermediateDirectories: true)
        try """
        ---
        name: Release Notes Writer
        description: Build release notes from git history.
        ---
        """.write(to: releaseNotes.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let reviewer = root.appendingPathComponent("reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: reviewer, withIntermediateDirectories: true)
        try """
        # Reviewer

        Finds bugs and regression risks.
        """.write(to: reviewer.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skills = try manager.discoverSkills()

        XCTAssertEqual(skills.map(\.name), ["Release Notes Writer", "Reviewer"])
        XCTAssertEqual(skills.first?.description, "Build release notes from git history.")
        XCTAssertEqual(skills.last?.description, "Finds bugs and regression risks.")
    }

    func testDiscoverSkillsParsesVersionAuthorAndSourceMetadata() throws {
        let root = manager.sharedRootURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let reviewer = root.appendingPathComponent("reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: reviewer, withIntermediateDirectories: true)
        try """
        ---
        name: Reviewer
        description: Finds diff risks.
        version: 1.2.3
        author: SuperIsland
        ---
        """.write(to: reviewer.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let source = SkillSourceMetadata(
            repoFullName: "owner/reviewer-skills",
            repoURL: "https://github.com/owner/reviewer-skills",
            cloneURL: "https://github.com/owner/reviewer-skills.git",
            sourcePath: ".",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedRevision: nil,
            cachedRemoteRevision: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(source)
        try data.write(to: reviewer.appendingPathComponent(".superisland-skill-source.json"), options: .atomic)

        let skills = try manager.discoverSkills()
        let skill = try XCTUnwrap(skills.first)

        XCTAssertEqual(skill.version, "1.2.3")
        XCTAssertEqual(skill.author, "SuperIsland")
        XCTAssertEqual(skill.sourceMetadata?.repoFullName, "owner/reviewer-skills")
        XCTAssertTrue(skill.hasUpdateSource)
        XCTAssertTrue(skill.isUpdatable)
    }

    func testLinkCreatesSymlinkForSupportedAgent() throws {
        try manager.ensureSharedRootExists()

        try manager.link(.claude)

        let claudePath = SkillAgentID.claude.skillsURL(homeDirectory: homeDirectory)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: claudePath.path)
        let resolved = URL(fileURLWithPath: destination, relativeTo: claudePath.deletingLastPathComponent()).standardizedFileURL
        XCTAssertEqual(resolved, manager.sharedRootURL.standardizedFileURL)

        let snapshot = manager.agentSnapshots().first(where: { $0.agent == .claude })
        XCTAssertEqual(snapshot?.state, .linked)
    }

    func testRepairGlobalAgentLinksCreatesMissingLinks() throws {
        try manager.ensureSharedRootExists()

        let summary = manager.repairGlobalAgentLinks()

        XCTAssertTrue(summary.linkedAgents.contains(.claude))
        XCTAssertTrue(summary.linkedAgents.contains(.cursor))
        XCTAssertEqual(summary.conflictCount, 0)

        let claudePath = SkillAgentID.claude.skillsURL(homeDirectory: homeDirectory)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: claudePath.path)
        let resolved = URL(fileURLWithPath: destination, relativeTo: claudePath.deletingLastPathComponent()).standardizedFileURL
        XCTAssertEqual(resolved, manager.sharedRootURL.standardizedFileURL)
    }

    func testRepairGlobalAgentLinksLeavesConflictsUntouched() throws {
        try manager.ensureSharedRootExists()

        let claudePath = SkillAgentID.claude.skillsURL(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: claudePath, withIntermediateDirectories: true)
        try "# Conflict\n\nLocal dir.".write(
            to: claudePath.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let summary = manager.repairGlobalAgentLinks()

        XCTAssertTrue(summary.conflictAgents.contains(.claude))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudePath.appendingPathComponent("SKILL.md").path))
        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: claudePath.path))
    }

    func testResolveConflictImportsRemovesOldDirectoryAndLinksAgentDirectory() throws {
        try manager.ensureSharedRootExists()

        let claudePath = SkillAgentID.claude.skillsURL(homeDirectory: homeDirectory)
        let localSkill = claudePath.appendingPathComponent("legacy-reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: localSkill, withIntermediateDirectories: true)
        try """
        ---
        name: Legacy Reviewer
        description: Migrated from Claude global directory.
        ---
        """.write(
            to: localSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let summary = try manager.resolveConflict(for: .claude)

        XCTAssertEqual(summary.agent, .claude)
        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)

        let sharedSkill = manager.sharedRootURL.appendingPathComponent("legacy-reviewer/SKILL.md", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedSkill.path))

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: claudePath.path)
        let resolved = URL(fileURLWithPath: destination, relativeTo: claudePath.deletingLastPathComponent()).standardizedFileURL
        XCTAssertEqual(resolved, manager.sharedRootURL.standardizedFileURL)

        let siblingEntries = try FileManager.default.contentsOfDirectory(
            at: claudePath.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(siblingEntries.contains(where: { $0.lastPathComponent.hasPrefix("skills.backup-") }))
    }

    func testCodexSnapshotIsNativeSharedRoot() {
        let snapshot = manager.agentSnapshots().first(where: { $0.agent == .codex })
        XCTAssertEqual(snapshot?.state, .native)
        XCTAssertEqual(snapshot?.skillsURL.standardizedFileURL, manager.sharedRootURL.standardizedFileURL)
    }

    func testImportSkillsOnlyUsesLikelySkillDirectories() throws {
        let importRoot = temporaryRoot.appendingPathComponent("repo", isDirectory: true)
        let firstSkill = importRoot.appendingPathComponent("skills/frontend-design", isDirectory: true)
        let secondSkill = importRoot.appendingPathComponent(".claude/skills/reviewer", isDirectory: true)
        let ignoredDoc = importRoot.appendingPathComponent("docs/skill-template", isDirectory: true)

        try FileManager.default.createDirectory(at: firstSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredDoc, withIntermediateDirectories: true)

        try "# Frontend Design\n\nMakes polished UIs.".write(
            to: firstSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Reviewer\n\nChecks diffs carefully.".write(
            to: secondSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Template\n\nShould not be imported.".write(
            to: ignoredDoc.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let installed = try manager.importSkills(from: importRoot)

        XCTAssertEqual(Set(installed.map(\.folderName)), ["frontend-design", "reviewer"])
        XCTAssertFalse(installed.contains(where: { $0.folderName == "skill-template" }))
    }

    func testDiscoverSkillsIncludesLegacyAgentDirectory() throws {
        let legacyRoot = homeDirectory.appendingPathComponent(".agent/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)

        let legacySkill = legacyRoot.appendingPathComponent("legacy-reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: legacySkill, withIntermediateDirectories: true)
        try "# Legacy Reviewer\n\nFound in legacy storage.".write(
            to: legacySkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let skills = try manager.discoverSkills()
        let skill = try XCTUnwrap(skills.first(where: { $0.folderName == "legacy-reviewer" }))

        XCTAssertFalse(skill.isSharedLibrarySkill)
        XCTAssertEqual(skill.storageKind, .legacyAgent)
    }

    func testImportSkillsToSharedLibraryImportsAllExternalSkills() throws {
        let legacyRoot = homeDirectory.appendingPathComponent(".agent/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)

        for name in ["legacy-a", "legacy-b"] {
            let directory = legacyRoot.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "# \(name)\n\nImported in batch.".write(
                to: directory.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let externalSkills = try manager.discoverSkills().filter { !$0.isSharedLibrarySkill }
        let summary = try manager.importSkillsToSharedLibrary(externalSkills)
        let sharedSkills = try manager.discoverSkills().filter(\.isSharedLibrarySkill)

        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertTrue(sharedSkills.contains(where: { $0.folderName == "legacy-a" }))
        XCTAssertTrue(sharedSkills.contains(where: { $0.folderName == "legacy-b" }))
    }

    func testImportSkillsToSharedLibrarySkipsDuplicateNames() throws {
        let sharedRoot = manager.sharedRootURL
        try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
        let existing = sharedRoot.appendingPathComponent("reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "# Reviewer\n\nShared already exists.".write(
            to: existing.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let legacyRoot = homeDirectory.appendingPathComponent(".agent/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let duplicate = legacyRoot.appendingPathComponent("reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: true)
        try "# Reviewer\n\nLegacy duplicate.".write(
            to: duplicate.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let externalSkills = try manager.discoverSkills().filter { !$0.isSharedLibrarySkill }
        let summary = try manager.importSkillsToSharedLibrary(externalSkills)

        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
    }

    func testImportSkillToSharedLibraryRejectsProjectScopedSkill() throws {
        let projectRoot = temporaryRoot.appendingPathComponent("workspace/.claude/skills/reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try "# Reviewer\n\nProject scoped.".write(
            to: projectRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let skill = InstalledSkill(
            directoryURL: projectRoot,
            name: "Reviewer",
            description: "Project scoped.",
            version: nil,
            author: nil,
            modifiedAt: nil,
            sourceMetadata: nil,
            storageKind: .agent(.claude),
            isAdoptableToSharedLibrary: false
        )

        XCTAssertThrowsError(try manager.importSkillToSharedLibrary(skill)) { error in
            XCTAssertEqual(error as? SkillPlatformError, .projectScopedSkillCannotBeImported)
        }
    }

    func testPreviewDocumentLoadsLocalSkillMarkdown() throws {
        let sharedRoot = manager.sharedRootURL
        try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)

        let directory = sharedRoot.appendingPathComponent("reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        # Reviewer

        Checks risky diffs.
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = try XCTUnwrap(manager.discoverSkills().first(where: { $0.folderName == "reviewer" }))
        let document = try manager.previewDocument(for: skill)

        XCTAssertEqual(document.title, "Reviewer")
        XCTAssertTrue(document.subtitle.contains("SKILL.md"))
        XCTAssertTrue(document.body.contains("Checks risky diffs."))
        XCTAssertTrue(document.metadata.contains(where: { $0.contains("Storage") }))
    }

    func testParseInstallReferenceExtractsRepositoryAndSkillName() throws {
        let parsed = try XCTUnwrap(
            manager.parseInstallReference(
                from: "npx skills add http://gitlab.mayidata.com/galaxy-backend/vibe_coding_tookit/-/tree/main/skills --skill zhangtian-test-loop"
            )
        )

        XCTAssertEqual(
            parsed.reference,
            "http://gitlab.mayidata.com/galaxy-backend/vibe_coding_tookit/-/tree/main/skills"
        )
        XCTAssertEqual(parsed.skillName, "zhangtian-test-loop")
    }

    func testNormalizeRepositoryReferenceSupportsGitLabTreeURLs() throws {
        let normalized = try manager.normalizeRepositoryReference(
            "http://gitlab.mayidata.com/galaxy-backend/vibe_coding_tookit/-/tree/main/skills",
            preferredSkillName: "zhangtian-test-loop"
        )

        XCTAssertEqual(
            normalized.cloneURL.absoluteString,
            "http://gitlab.mayidata.com/galaxy-backend/vibe_coding_tookit.git"
        )
        XCTAssertEqual(
            normalized.htmlURL.absoluteString,
            "http://gitlab.mayidata.com/galaxy-backend/vibe_coding_tookit"
        )
        XCTAssertEqual(normalized.repoFullName, "galaxy-backend/vibe_coding_tookit")
        XCTAssertEqual(normalized.repoName, "vibe_coding_tookit")
        XCTAssertEqual(normalized.sourceRootPath, "skills")
        XCTAssertEqual(normalized.preferredSkillName, "zhangtian-test-loop")
    }

    func testNormalizeRepositoryReferenceSupportsNestedGitLabTreePaths() throws {
        let normalized = try manager.normalizeRepositoryReference(
            "http://gitlab.mayidata.com/guandata/skills/-/tree/main/go-skills",
            preferredSkillName: "yuque-skill"
        )

        XCTAssertEqual(normalized.repoFullName, "guandata/skills")
        XCTAssertEqual(normalized.sourceRootPath, "go-skills")
        XCTAssertEqual(normalized.preferredSkillName, "yuque-skill")
    }

    func testParseSkillsShLeaderboardHTMLExtractsRankAndRepository() throws {
        let html = #"<a class="group grid lg:grid-cols-[auto_1fr_auto] items-center gap-3" href="/openai/codex/reviewer"><span class="text-sm lg:text-base text-(--ds-gray-600) font-mono">7</span><h3 class="font-semibold text-foreground truncate whitespace-nowrap">Reviewer</h3><p class="text-xs lg:text-sm text-(--ds-gray-600) font-mono mt-0.5 lg:mt-0 truncate">openai/codex-skills</p><span class="font-mono text-sm text-foreground">1.2k</span></a>"#

        let item = try XCTUnwrap(manager.parseSkillsShLeaderboardHTML(html).first)

        XCTAssertEqual(item.source, .skillsSh)
        XCTAssertEqual(item.title, "Reviewer")
        XCTAssertEqual(item.repoFullName, "openai/codex-skills")
        XCTAssertEqual(item.rank, 7)
        XCTAssertEqual(item.installsText, "1.2k")
        XCTAssertEqual(item.installReference, "openai/codex-skills")
    }

    func testParseMayidataListingHTMLExtractsRepoTagsAndDate() throws {
        let html = #"<a class="skill-card" href="/skills/reviewer"><p class="skill-card__repo">guandata/reviewer</p><h3>Reviewer</h3><p>Checks risky diffs.</p><p class="skill-card__author">alice</p><p class="skill-card__updated-at">更新于 <!-- -->2026/4/1</p><span class="skill-pill">review</span><span class="skill-pill">safety</span></a>"#

        let item = try XCTUnwrap(manager.parseMayidataListingHTML(html).first)

        XCTAssertEqual(item.source, .mayidata)
        XCTAssertEqual(item.title, "Reviewer")
        XCTAssertEqual(item.repoFullName, "guandata/reviewer")
        XCTAssertEqual(item.description, "Checks risky diffs.")
        XCTAssertEqual(item.topics, ["review", "safety"])
        XCTAssertEqual(item.installReference, "guandata/reviewer")
        XCTAssertEqual(item.updatedAt, manager.parseMayidataDate("2026/4/1"))
    }

    func testImportSkillsToSharedLibrarySkipsProjectScopedSkillsInBatch() throws {
        let projectRoot = temporaryRoot.appendingPathComponent("workspace/.claude/skills/reviewer", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try "# Reviewer\n\nProject scoped.".write(
            to: projectRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let skill = InstalledSkill(
            directoryURL: projectRoot,
            name: "Reviewer",
            description: "Project scoped.",
            version: nil,
            author: nil,
            modifiedAt: nil,
            sourceMetadata: nil,
            storageKind: .agent(.claude),
            isAdoptableToSharedLibrary: false
        )

        let summary = try manager.importSkillsToSharedLibrary([skill])

        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
    }
}
