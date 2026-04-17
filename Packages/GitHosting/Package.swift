// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHosting",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GitHosting", targets: ["GitHosting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.8.0"),
        .package(path: "../GitCore"),
    ],
    targets: [
        .target(
            name: "GitHosting",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "GitCore", package: "GitCore"),
            ]
        ),
    ]
)
