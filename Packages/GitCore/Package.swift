// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GitCore", targets: ["GitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.15.0"),
        .package(path: "../ProcessExecution"),
        .package(path: "../ActivityLog"),
    ],
    targets: [
        .target(
            name: "GitCore",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "ProcessExecution", package: "ProcessExecution"),
                .product(name: "ActivityLog", package: "ActivityLog"),
            ]
        ),
        .testTarget(
            name: "GitCoreTests",
            dependencies: ["GitCore"]
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
