// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeSessionsManager",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ClaudeSessionsCore"),
        .executableTarget(name: "ClaudeSessionsManager", dependencies: ["ClaudeSessionsCore"]),
        .testTarget(name: "ClaudeSessionsCoreTests", dependencies: ["ClaudeSessionsCore"]),
    ],
    swiftLanguageModes: [.v5]
)
