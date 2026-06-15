// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftAgent",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "swift-agent", targets: ["SwiftAgentCLI"]),
        .library(name: "SwiftAgentCore", targets: ["SwiftAgentCore"]),
        .executable(name: "SwiftAgentApp", targets: ["SwiftAgentApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftAgentCore",
            path: "Sources/SwiftAgentCore"
        ),
        .executableTarget(
            name: "SwiftAgentCLI",
            dependencies: [
                "SwiftAgentCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwiftAgentCLI"
        ),
        .executableTarget(
            name: "SwiftAgentApp",
            dependencies: ["SwiftAgentCore"],
            path: "Sources/SwiftAgentApp"
        ),
        .testTarget(
            name: "SwiftAgentCoreTests",
            dependencies: ["SwiftAgentCore"],
            path: "Tests/SwiftAgentCoreTests"
        ),
        .testTarget(
            name: "SwiftAgentCLITests",
            dependencies: ["SwiftAgentCLI"],
            path: "Tests/SwiftAgentCLITests"
        ),
        .testTarget(
            name: "SwiftAgentAppTests",
            dependencies: ["SwiftAgentApp"],
            path: "Tests/SwiftAgentAppTests"
        ),
    ]
)
