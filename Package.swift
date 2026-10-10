// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BambuLight",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BambuLight", path: "Sources/BambuLight"),
        .testTarget(name: "BambuLightTests", dependencies: ["BambuLight"], path: "Tests/BambuLightTests"),
    ]
)
