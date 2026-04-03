// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "ActionButtons",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "ActionButtons", targets: ["ActionButtons"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.25.3"),
		.package(path: "../AppUI"),
		.package(path: "../ToolsIntegration"),
	],
	targets: [
		.target(
			name: "ActionButtons",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "ToolsIntegration", package: "ToolsIntegration"),
			]
		),
	]
)
