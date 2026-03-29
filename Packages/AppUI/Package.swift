// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
    ],
    targets: [
        .target(
            name: "AppUI",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
