// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "DiskUsageFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "DiskUsageFeature", targets: ["DiskUsageFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1", traits: ["ComposableArchitecture2Deprecations", "ComposableArchitecture2DeprecationOverloads"]),
		.package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.9.1"),
		.package(path: "../AppUI"),
		.package(path: "../ActivityLog"),
	],
	targets: [
		.target(
			name: "DiskUsageFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "Sharing", package: "swift-sharing"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "ActivityLog", package: "ActivityLog"),
			]
		),
		.testTarget(
			name: "DiskUsageFeatureTests",
			dependencies: [
				"DiskUsageFeature",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
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
