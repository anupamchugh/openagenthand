// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenAgentHand",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "OpenAgentHandCore", targets: ["OpenAgentHandCore"])],
    targets: [
        .target(name: "OpenAgentHandCore"),
        .testTarget(name: "OpenAgentHandCoreTests", dependencies: ["OpenAgentHandCore"]),
    ]
)
