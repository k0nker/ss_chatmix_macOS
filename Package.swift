// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sschatmix",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "sschatmix", targets: ["sschatmix"]),
        .executable(name: "SSChatMixApp", targets: ["SSChatMixApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // CLI executable
        .executableTarget(
            name: "sschatmix",
            dependencies: [
                "SSChatMixCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Menu bar app
        .executableTarget(
            name: "SSChatMixApp",
            dependencies: ["SSChatMixCore"]
        ),
        // Shared core library
        .target(
            name: "SSChatMixCore",
            dependencies: []
        )
    ]
)
