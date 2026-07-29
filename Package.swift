// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLidKeeper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CodexLidKeeperCore",
            targets: ["CodexLidKeeperCore"]
        ),
        .executable(
            name: "codex-lid-keeper",
            targets: ["CodexLidKeeperCLI"]
        ),
        .executable(
            name: "codex-lid-keeper-self-test",
            targets: ["CodexLidKeeperSelfTests"]
        )
    ],
    targets: [
        .target(
            name: "CodexLidKeeperCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexLidKeeperCLI",
            dependencies: ["CodexLidKeeperCore"]
        ),
        .executableTarget(
            name: "CodexLidKeeperSelfTests",
            dependencies: ["CodexLidKeeperCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
