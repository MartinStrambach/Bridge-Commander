// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProcessExecution",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ProcessExecution", targets: ["ProcessExecution"]),
    ],
    dependencies: [
        .package(path: "../ActivityLog"),
    ],
    targets: [
        .target(
            name: "ProcessExecution",
            dependencies: [
                .product(name: "ActivityLog", package: "ActivityLog"),
            ]
        ),
        .testTarget(
            name: "ProcessExecutionTests",
            dependencies: ["ProcessExecution"]
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
