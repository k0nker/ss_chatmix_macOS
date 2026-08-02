// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sschatmix",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "sschatmix", targets: ["sschatmix"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "sschatmix",
            dependencies: [
                "SSChatMixCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "SSChatMixCore",
            dependencies: []
        )
    ]
)
