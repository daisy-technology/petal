// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Petal",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PetalCore"),
        .executableTarget(name: "Petal", dependencies: ["PetalCore"]),
        .testTarget(name: "PetalCoreTests", dependencies: ["PetalCore"]),
    ]
)
