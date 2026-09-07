// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "DiffModelMapping", targets: ["DiffModelMapping"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
        .package(path: "../GitCore"),
    ],
    targets: [
        // Stays free of any git dependency: AppUI owns its own diff display models.
        .target(
            name: "AppUI",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        // Converts GitCore's diff models into AppUI's, for every feature that renders a diff.
        .target(
            name: "DiffModelMapping",
            dependencies: [
                "AppUI",
                .product(name: "GitCore", package: "GitCore"),
            ]
        ),
    ]
)
