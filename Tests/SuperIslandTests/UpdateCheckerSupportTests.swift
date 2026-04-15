import XCTest
@testable import SuperIsland

final class UpdateCheckerSupportTests: XCTestCase {
    func testVersionComparatorHandlesMissingPatchSegments() {
        XCTAssertTrue(UpdateVersioning.isRemoteVersionNewer(remote: "1.2.1", local: "1.2"))
        XCTAssertFalse(UpdateVersioning.isRemoteVersionNewer(remote: "1.2", local: "1.2.0"))
        XCTAssertFalse(UpdateVersioning.isRemoteVersionNewer(remote: "1.1.9", local: "1.2"))
    }

    func testManifestDecodesLegacyReleaseUrlKeyAndNormalizesVersion() throws {
        let json = Data(#"{"version":"v1.4.0","downloadUrl":"https://example.com/app.dmg","releaseUrl":"https://example.com/release"}"#.utf8)
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: json)

        XCTAssertEqual(manifest.normalizedVersion, "1.4.0")
        XCTAssertEqual(manifest.downloadUrl, "https://example.com/app.dmg")
        XCTAssertEqual(manifest.releaseURL, "https://example.com/release")
    }

    func testResolveInstallTargetPathPrefersExistingApplicationInstall() {
        let resolved = UpdateInstallPaths.resolveInstallTargetPath(
            currentAppPath: "/private/var/folders/xyz/AppTranslocation/SuperIsland.app",
            fileExists: { $0 == "/Applications/SuperIsland.app" },
            homeDirectoryPath: "/Users/tester"
        )

        XCTAssertEqual(resolved, "/Applications/SuperIsland.app")
    }

    func testResolveInstallTargetPathFallsBackToUserApplicationsForMountedVolume() {
        let resolved = UpdateInstallPaths.resolveInstallTargetPath(
            currentAppPath: "/Volumes/SuperIsland/SuperIsland.app",
            fileExists: { _ in false },
            homeDirectoryPath: "/Users/tester"
        )

        XCTAssertEqual(resolved, "/Users/tester/Applications/SuperIsland.app")
    }
}
