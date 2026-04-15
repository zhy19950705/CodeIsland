import XCTest
@testable import SuperIsland

final class SkillPlatformUpdateDetectionTests: XCTestCase {
    private var temporaryRoot: URL!
    private var homeDirectory: URL!
    private var manager: SkillManager!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillPlatformUpdateDetectionTests-\(UUID().uuidString)", isDirectory: true)
        homeDirectory = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        manager = SkillManager(homeDirectory: homeDirectory)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testRefreshAvailableUpdatesMarksSkillWhenRemoteHeadMoves() async throws {
        let repository = try createRepositoryWithSkill(named: "reviewer")
        let skillDirectory = try makeInstalledSkillDirectory(
            folderName: "reviewer",
            metadata: SkillSourceMetadata(
                repoFullName: "local/reviewer",
                repoURL: repository.remoteURL.path,
                cloneURL: repository.remoteURL.path,
                sourcePath: ".",
                installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                installedRevision: repository.initialRevision,
                cachedRemoteRevision: repository.initialRevision
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillDirectory.path))

        var skills = try manager.discoverSkills()
        XCTAssertEqual(skills.count, 1)
        XCTAssertFalse(try XCTUnwrap(skills.first).isUpdatable)

        let latestRevision = try appendRemoteCommit(
            in: repository.workingURL,
            folderName: "reviewer"
        )
        XCTAssertNotEqual(latestRevision, repository.initialRevision)

        let didChange = await manager.refreshAvailableUpdates(for: skills)
        XCTAssertTrue(didChange)

        skills = try manager.discoverSkills()
        let refreshedSkill = try XCTUnwrap(skills.first)
        XCTAssertEqual(refreshedSkill.sourceMetadata?.cachedRemoteRevision, latestRevision)
        XCTAssertTrue(refreshedSkill.isUpdatable)
    }

    func testLegacyMetadataStillFallsBackToUpdateButton() throws {
        _ = try makeInstalledSkillDirectory(
            folderName: "legacy-reviewer",
            metadata: SkillSourceMetadata(
                repoFullName: "owner/reviewer-skills",
                repoURL: "https://github.com/owner/reviewer-skills",
                cloneURL: nil,
                sourcePath: ".",
                installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                installedRevision: nil,
                cachedRemoteRevision: nil
            )
        )

        let skill = try XCTUnwrap(manager.discoverSkills().first)
        XCTAssertTrue(skill.hasUpdateSource)
        XCTAssertTrue(skill.isUpdatable)
    }

    // The local bare repository keeps the test deterministic and avoids external network dependencies.
    private func createRepositoryWithSkill(named folderName: String) throws -> (remoteURL: URL, workingURL: URL, initialRevision: String) {
        let remoteURL = temporaryRoot.appendingPathComponent("remote.git", isDirectory: true)
        let workingURL = temporaryRoot.appendingPathComponent("working", isDirectory: true)

        _ = try runGit(["init", "--bare", remoteURL.path], workingDirectory: temporaryRoot)
        _ = try runGit(["init", workingURL.path], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "branch", "-M", "main"], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "remote", "add", "origin", remoteURL.path], workingDirectory: temporaryRoot)

        let skillDirectory = workingURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: Reviewer
        description: Reviews code changes.
        ---
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        _ = try runGit(["-C", workingURL.path, "add", "."], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "commit", "-m", "Initial skill"], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "push", "--set-upstream", "origin", "main"], workingDirectory: temporaryRoot)

        let initialRevision = try runGit(["-C", workingURL.path, "rev-parse", "HEAD"], workingDirectory: temporaryRoot)
        return (remoteURL, workingURL, initialRevision)
    }

    private func appendRemoteCommit(in workingURL: URL, folderName: String) throws -> String {
        try "\nUpdated content.\n".appendLine(to: workingURL.appendingPathComponent("\(folderName)/SKILL.md"))
        _ = try runGit(["-C", workingURL.path, "add", "."], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "commit", "-m", "Update skill"], workingDirectory: temporaryRoot)
        _ = try runGit(["-C", workingURL.path, "push", "origin", "main"], workingDirectory: temporaryRoot)
        return try runGit(["-C", workingURL.path, "rev-parse", "HEAD"], workingDirectory: temporaryRoot)
    }

    private func makeInstalledSkillDirectory(folderName: String, metadata: SkillSourceMetadata) throws -> URL {
        let skillDirectory = manager.sharedRootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: Reviewer
        description: Reviews code changes.
        ---
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try manager.writeSourceMetadata(metadata, to: skillDirectory)
        return skillDirectory
    }

    // Git author environment is set per command so the tests work on clean machines without global git config.
    private func runGit(_ arguments: [String], workingDirectory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = [
            "GIT_AUTHOR_NAME": "SuperIsland Tests",
            "GIT_AUTHOR_EMAIL": "tests@superisland.local",
            "GIT_COMMITTER_NAME": "SuperIsland Tests",
            "GIT_COMMITTER_EMAIL": "tests@superisland.local",
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}

private extension String {
    // Appending in place keeps the test fixture simple and avoids shell-specific redirection behavior.
    func appendLine(to url: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (existing + self).write(to: url, atomically: true, encoding: .utf8)
    }
}
