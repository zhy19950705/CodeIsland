// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperIsland",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Down-gfm keeps GitHub-style tables and fenced blocks working inside the existing WebKit preview pipeline.
        .package(url: "https://github.com/stackotter/Down-gfm", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "SuperIslandCore",
            path: "Sources/SuperIslandCore"
        ),
        .executableTarget(
            name: "SuperIsland",
            dependencies: [
                "SuperIslandCore",
                // The package product is still named Down, even though it comes from the Down-gfm repository.
                .product(name: "Down", package: "Down-gfm")
            ],
            path: "Sources/SuperIsland",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "superisland-bridge",
            dependencies: ["SuperIslandCore"],
            path: "Sources/SuperIslandBridge"
        ),
        .testTarget(
            name: "SuperIslandCoreTests",
            dependencies: ["SuperIslandCore"],
            path: "Tests/SuperIslandCoreTests"
        ),
        .testTarget(
            name: "SuperIslandTests",
            dependencies: ["SuperIsland"],
            path: "Tests/SuperIslandTests"
        ),
    ]
)
