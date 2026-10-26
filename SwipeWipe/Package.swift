// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// StrictConcurrency is enabled by default in Swift 6.0 language mode.

import PackageDescription

let package = Package(
    name: "SwipeWipe",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwipeWipeCore",
            targets: ["SwipeWipeCore"]
        ),
        .executable(
            name: "SwipeWipeApp",
            targets: ["SwipeWipeApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwipeWipeCore",
            dependencies: [],
            path: "Sources/SwipeWipeCore"
        ),
        .executableTarget(
            name: "SwipeWipeApp",
            dependencies: ["SwipeWipeCore"],
            path: "Sources/SwipeWipeApp"
        ),
        .testTarget(
            name: "SwipeWipeCoreTests",
            dependencies: ["SwipeWipeCore"],
            path: "Tests/SwipeWipeCoreTests"
        )
    ]
)
