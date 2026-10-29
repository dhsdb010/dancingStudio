// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PoseKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoseKit", targets: ["PoseKit"])
    ],
    targets: [
        .target(name: "PoseKit"),
        .testTarget(name: "PoseKitTests", dependencies: ["PoseKit"])
    ]
)
