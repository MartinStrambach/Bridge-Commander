// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "RepositoryFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "RepositoryFeature", targets: ["RepositoryFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.25.3"),
		.package(path: "../GitCore"),
		.package(path: "../AppUI"),
		.package(path: "../Settings"),
		.package(path: "../ToolsIntegration"),
		.package(path: "../TerminalFeature"),
		.package(path: "../GitActionsMenu"),
		.package(path: "../ActionButtons"),
	],
	targets: [
		.target(
			name: "RepositoryFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "GitCore", package: "GitCore"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "Settings", package: "Settings"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
				.product(name: "TerminalFeature", package: "TerminalFeature"),
				.product(name: "GitActionsMenu", package: "GitActionsMenu"),
				.product(name: "ActionButtons", package: "ActionButtons"),
			]
		),
	]
)
