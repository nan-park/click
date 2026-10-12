// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClickCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ClickCore", targets: ["ClickCore"]),
        .executable(name: "clickcore-cli", targets: ["clickcore-cli"]),
    ],
    targets: [
        .target(name: "ClickCore"),
        .executableTarget(name: "clickcore-cli", dependencies: ["ClickCore"]),
        .testTarget(name: "ClickCoreTests", dependencies: ["ClickCore"]),
    ]
)
