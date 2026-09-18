// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OtterStats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OtterStatsCore", targets: ["OtterStatsCore"]),
        .executable(name: "OtterStats", targets: ["OtterStats"]),
    ],
    targets: [
        .target(
            name: "OtterStatsCore",
            path: "Sources/OtterStatsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "OtterStats",
            dependencies: ["OtterStatsCore"],
            path: "Sources/OtterStats"
        ),
        .testTarget(
            name: "OtterStatsCoreTests",
            dependencies: ["OtterStatsCore"],
            path: "Tests/OtterStatsCoreTests"
        ),
    ]
)
