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
        ),
        .executable(
            name: "Meeting007App",
            targets: ["Meeting007App"]
        )
    ],
    targets: [
        .target(
            name: "Meeting007Core"
        ),
        .executableTarget(
            name: "Meeting007CoreChecks",
            dependencies: ["Meeting007Core"]
        ),
        .executableTarget(
            name: "Meeting007App",
            dependencies: ["Meeting007Core"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Meeting007App/Info.plist"
                ])
            ]
        )
    ]
)
