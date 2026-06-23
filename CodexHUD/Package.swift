// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexHUD",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexHUDCore", targets: ["CodexHUDCore"]),
        .executable(name: "CodexHUD", targets: ["CodexHUD"])
    ],
    targets: [
        .target(name: "CodexHUDCore"),
        .executableTarget(
            name: "CodexHUD",
            dependencies: ["CodexHUDCore"]),
        .testTarget(
            name: "CodexHUDCoreTests",
            dependencies: ["CodexHUDCore"])
    ]
)
