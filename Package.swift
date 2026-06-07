// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Meeting007",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Meeting007Core",
            targets: ["Meeting007Core"]
        ),
        .executable(
            name: "Meeting007CoreChecks",
            targets: ["Meeting007CoreChecks"]
        )
    ],
    targets: [
        .target(
            name: "Meeting007Core"
        ),
        .executableTarget(
            name: "Meeting007CoreChecks",
            dependencies: ["Meeting007Core"]
        )
    ]
)
