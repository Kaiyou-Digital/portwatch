// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "portwatch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PortwatchCore"),
        .executableTarget(name: "portwatch", dependencies: ["PortwatchCore"]),
        .testTarget(name: "PortwatchCoreTests", dependencies: ["PortwatchCore"]),
    ]
)
