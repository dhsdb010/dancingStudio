// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChoreoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChoreoKit", targets: ["ChoreoKit"])
    ],
    dependencies: [
        .package(path: "../PoseKit")
    ],
    targets: [
        .target(name: "ChoreoKit", dependencies: ["PoseKit"]),
        .testTarget(name: "ChoreoKitTests", dependencies: ["ChoreoKit"])
    ]
)
