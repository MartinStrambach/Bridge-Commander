// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "YouTrackMenu",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "YouTrackMenu", targets: ["YouTrackMenu"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(path: "../AppUI"),
		.package(path: "../ToolsIntegration"),
	],
	targets: [
		.target(
			name: "YouTrackMenu",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
			]
		),
		.testTarget(
			name: "YouTrackMenuTests",
			dependencies: [
				"YouTrackMenu",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
			]
		),
	]
)
