// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "audio-engine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AudioEngine",
            targets: ["AudioEngine"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.21.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0")
    ],
    targets: [
        .target(
            name: "AudioEngine",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/AudioEngine",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"],
            path: "Tests/AudioEngineTests"
        ),
        .executableTarget(
            name: "audio-engine-smoke",
            dependencies: ["AudioEngine"],
            path: "Sources/SmokeTest"
        ),
        .executableTarget(
            name: "verify-mastering",
            dependencies: ["AudioEngine"],
            path: "Sources/VerifyMastering"
        )
    ]
)
