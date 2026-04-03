// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitActionsMenu",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GitActionsMenu", targets: ["GitActionsMenu"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.25.3"),
        .package(path: "../GitCore"),
        .package(path: "../AppUI"),
    ],
    targets: [
        .target(
            name: "GitActionsMenu",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GitCore", package: "GitCore"),
                .product(name: "AppUI", package: "AppUI"),
            ]
        ),
    ]
)
