// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "HomerFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "HomerFeature", targets: ["HomerFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.15.0"),
		.package(path: "../AppUI"),
	],
	targets: [
		.target(
			name: "HomerFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "AppUI", package: "AppUI"),
			]
		),
		.testTarget(
			name: "HomerFeatureTests",
			dependencies: [
				"HomerFeature",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				// The `.dependencies` trait, which gives each test its own `@Shared` app storage.
				.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
			]
		),
	]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
