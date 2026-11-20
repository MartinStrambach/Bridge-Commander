// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "DependencyGraphFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "DependencyGraphFeature", targets: ["DependencyGraphFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1", traits: ["ComposableArchitecture2Deprecations", "ComposableArchitecture2DeprecationOverloads"]),
		.package(path: "../AppUI"),
		.package(path: "../GitCore"),
	],
	targets: [
		.target(
			name: "DependencyGraphFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "GitCore", package: "GitCore"),
			]
		),
		.testTarget(
			name: "DependencyGraphFeatureTests",
			dependencies: [
				"DependencyGraphFeature",
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
