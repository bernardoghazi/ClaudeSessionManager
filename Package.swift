// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeSessionManager",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ClaudeSessionCore"),
        .executableTarget(name: "ClaudeSessionManager", dependencies: ["ClaudeSessionCore"]),
        .testTarget(name: "ClaudeSessionCoreTests", dependencies: ["ClaudeSessionCore"]),
    ],
    swiftLanguageModes: [.v5]
)
