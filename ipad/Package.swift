// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LuminaCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LuminaCore", targets: ["LuminaCore"]),
    ],
    targets: [
        .target(
            name: "LuminaCore",
            path: "LuminaShared",
            exclude: ["SharedStore.swift"],
            sources: ["Models.swift", "APIClient.swift"]
        ),
        .testTarget(
            name: "LuminaCoreTests",
            dependencies: ["LuminaCore"],
            path: "LuminaPadTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
