// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TerminalFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TerminalFeature", targets: ["TerminalFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.12.0"),
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
    ]
)
