// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BridgeCommander",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "BridgeCommander",
            targets: ["BridgeCommander"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BridgeCommander",
            path: ".",
            sources: [
                "BridgeCommanderApp.swift",
                "Models/Repository.swift",
                "ViewModels/RepositoryScanner.swift",
                "Views/ContentView.swift",
                "Views/RepositoryRowView.swift",
                "Helpers/GitDetector.swift",
                "Helpers/TerminalLauncher.swift"
            ]
        )
    ]
)
