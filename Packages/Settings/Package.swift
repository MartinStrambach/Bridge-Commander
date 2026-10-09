// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1", traits: ["ComposableArchitecture2Deprecations", "ComposableArchitecture2DeprecationOverloads"]),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.1"),
        .package(path: "../ToolsIntegration"),
        .package(path: "../GitHosting"),
        .package(path: "../AppUI"),
        .package(path: "../ActivityLog"),
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "ToolsIntegration", package: "ToolsIntegration"),
                .product(name: "GitHosting", package: "GitHosting"),
                .product(name: "AppUI", package: "AppUI"),
                .product(name: "ActivityLog", package: "ActivityLog"),
            ]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: [
                "Settings",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "ToolsIntegration", package: "ToolsIntegration"),
            ]
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .treatAllWarnings(as: .error),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
