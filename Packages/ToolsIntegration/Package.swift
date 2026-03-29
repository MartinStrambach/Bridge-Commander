// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ToolsIntegration",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ToolsIntegration", targets: ["ToolsIntegration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.8.0"),
        .package(path: "../ProcessExecution"),
        .package(path: "../Settings"),
    ],
    targets: [
        .target(
            name: "ToolsIntegration",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "ProcessExecution", package: "ProcessExecution"),
                .product(name: "Settings", package: "Settings"),
            ]
        ),
    ]
)
