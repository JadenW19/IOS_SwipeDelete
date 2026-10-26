// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
            path: "Sources/SwipeWipeCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SwipeWipeApp",
            dependencies: ["SwipeWipeCore"],
            path: "Sources/SwipeWipeApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwipeWipeCoreTests",
            dependencies: ["SwipeWipeCore"],
            path: "Tests/SwipeWipeCoreTests"
        )
    ]
)
