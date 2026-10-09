// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "TerminalFeature",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "TerminalFeature", targets: ["TerminalFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.99.0"),
		.package(path: "../AppUI"),
	],
	targets: [
		.target(
			name: "TerminalFeature",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "SwiftTerm", package: "SwiftTerm"),
				.product(name: "AppUI", package: "AppUI"),
			]
		),
		.testTarget(
			name: "TerminalFeatureTests",
			dependencies: [
				"TerminalFeature",
				.product(name: "SwiftTerm", package: "SwiftTerm"),
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
