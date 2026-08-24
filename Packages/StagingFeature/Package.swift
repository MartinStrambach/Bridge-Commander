// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StagingFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StagingFeature", targets: ["StagingFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
        .package(path: "../GitCore"),
        .package(path: "../AppUI"),
        .package(path: "../Settings"),
        .package(path: "../ToolsIntegration"),
    ],
    targets: [
        .target(
            name: "StagingFeature",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GitCore", package: "GitCore"),
                .product(name: "AppUI", package: "AppUI"),
                .product(name: "Settings", package: "Settings"),
                .product(name: "ToolsIntegration", package: "ToolsIntegration"),
            ]
        ),
        .testTarget(
            name: "StagingFeatureTests",
            dependencies: [
                "StagingFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GitCore", package: "GitCore"),
            ]
        ),
    ]
)
