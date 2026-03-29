// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.8.0"),
        .package(path: "../ToolsIntegration"),
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "ToolsIntegration", package: "ToolsIntegration"),
            ]
        ),
    ]
)
