// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ActivityLog",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ActivityLog", targets: ["ActivityLog"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ActivityLog",
            dependencies: []
        ),
        .testTarget(
            name: "ActivityLogTests",
            dependencies: ["ActivityLog"]
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
