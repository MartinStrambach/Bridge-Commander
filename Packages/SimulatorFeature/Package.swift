// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "SimulatorFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "SimulatorFeature", targets: ["SimulatorFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(path: "../AppUI"),
		.package(path: "../ProcessExecution"),
	],
	targets: [
		.target(
			name: "SimulatorFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "AppUI", package: "AppUI"),
				.product(name: "ProcessExecution", package: "ProcessExecution"),
				"ObjCExceptionCatching",
			]
		),
		.target(name: "ObjCExceptionCatching"),
		.testTarget(name: "SimulatorFeatureTests", dependencies: ["SimulatorFeature"]),
	]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .treatAllWarnings(as: .error),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
