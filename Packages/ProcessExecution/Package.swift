// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProcessExecution",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ProcessExecution", targets: ["ProcessExecution"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ProcessExecution",
            dependencies: []
        ),
    ]
)
