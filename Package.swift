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
        ),
        .executable(
            name: "codex-lid-keeper-app",
            targets: ["CodexLidKeeperApp"]
        )
    ],
    targets: [
        .target(
            name: "CodexLidKeeperCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexLidKeeperCLI",
            dependencies: ["CodexLidKeeperCore"]
        ),
        .executableTarget(
            name: "CodexLidKeeperSelfTests",
            dependencies: ["CodexLidKeeperCore"]
        ),
        .executableTarget(
            name: "CodexLidKeeperApp",
            dependencies: ["CodexLidKeeperCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
