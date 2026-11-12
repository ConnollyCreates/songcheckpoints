// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CheckpointCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CheckpointCore", targets: ["CheckpointCore"])
    ],
    targets: [
        .target(name: "CheckpointCore"),
        .testTarget(name: "CheckpointCoreTests", dependencies: ["CheckpointCore"])
    ]
)
