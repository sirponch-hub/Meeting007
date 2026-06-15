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
        .library(
            name: "Meeting007WhisperKit",
            targets: ["Meeting007WhisperKit"]
        ),
        .executable(
            name: "Meeting007CoreChecks",
            targets: ["Meeting007CoreChecks"]
        ),
        .executable(
            name: "Meeting007WhisperKitChecks",
            targets: ["Meeting007WhisperKitChecks"]
        ),
        .executable(
            name: "Meeting007App",
            targets: ["Meeting007App"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "Meeting007Core"
        ),
        .target(
            name: "Meeting007WhisperKit",
            dependencies: [
                "Meeting007Core",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "Meeting007CoreChecks",
            dependencies: ["Meeting007Core"]
        ),
        .executableTarget(
            name: "Meeting007WhisperKitChecks",
            dependencies: [
                "Meeting007Core",
                "Meeting007WhisperKit"
            ]
        ),
        .executableTarget(
            name: "Meeting007App",
            dependencies: [
                "Meeting007Core",
                "Meeting007WhisperKit"
            ],
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
