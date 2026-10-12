// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StreamCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StreamCore", targets: ["StreamCore"])
    ],
    targets: [
        .target(name: "StreamCore"),
        .testTarget(name: "StreamCoreTests", dependencies: ["StreamCore"])
    ]
)
