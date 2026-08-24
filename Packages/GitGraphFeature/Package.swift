// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitGraphFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GitGraphFeature", targets: ["GitGraphFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.1"),
        .package(path: "../GitCore"),
    ],
    targets: [
        .target(
            name: "GitGraphFeature",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "GitCore", package: "GitCore"),
            ]
        ),
        .testTarget(
            name: "GitGraphFeatureTests",
            dependencies: ["GitGraphFeature"]
        ),
    ]
)
