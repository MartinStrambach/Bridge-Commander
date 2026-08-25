// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "RepositoryFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "RepositoryFeature", targets: ["RepositoryFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(path: "../GitCore"),
		.package(path: "../GitGraphFeature"),
		.package(path: "../AppUI"),
		.package(path: "../Settings"),
		.package(path: "../ToolsIntegration"),
		.package(path: "../GitHosting"),
		.package(path: "../TerminalFeature"),
		.package(path: "../GitActionsMenu"),
		.package(path: "../ActionButtons"),
		.package(path: "../StagingFeature"),
	],
	targets: [
		.target(
			name: "RepositoryFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "GitCore", package: "GitCore"),
				.product(name: "GitGraphFeature", package: "GitGraphFeature"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "Settings", package: "Settings"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
				.product(name: "GitHosting", package: "GitHosting"),
				.product(name: "TerminalFeature", package: "TerminalFeature"),
				.product(name: "GitActionsMenu", package: "GitActionsMenu"),
				.product(name: "ActionButtons", package: "ActionButtons"),
				.product(name: "StagingFeature", package: "StagingFeature"),
			]
		),
		.testTarget(
			name: "RepositoryFeatureTests",
			dependencies: [
				"RepositoryFeature",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "GitCore", package: "GitCore"),
				.product(name: "GitActionsMenu", package: "GitActionsMenu"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
			]
		),
	]
)
