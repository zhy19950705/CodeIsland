// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SuperIslandCore",
            path: "Sources/SuperIslandCore"
        ),
        .executableTarget(
            name: "SuperIsland",
            dependencies: ["SuperIslandCore"],
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
