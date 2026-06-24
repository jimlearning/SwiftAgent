// swift-tools-version: 6.2
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
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(path: "Packages"),
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
            dependencies: [
                "SwiftAgentCore",
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "ClarcCore", package: "Packages"),
                .product(name: "ClarcChatKit", package: "Packages"),
            ],
            path: "Sources/SwiftAgentApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                // Embed Info.plist into the Mach-O __TEXT,__info_plist section so the
                // executable has a proper CFBundleIdentifier (fixes Xcode "Cannot index
                // window tabs due to missing main bundle identifier" and SwiftUI Previews).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SwiftAgentApp/Info.plist"
                ])
            ]
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
        .testTarget(
            name: "SwiftAgentAppUITests",
            dependencies: ["SwiftAgentApp"],
            path: "Tests/SwiftAgentAppUITests"
        ),
    ]
)
