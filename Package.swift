// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "SDOpenAIClient",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SDOpenAIClient",
            targets: ["SDOpenAIClient"]
        )
    ],
    targets: [
        .target(
            name: "SDOpenAIClient"
        ),
        .testTarget(
            name: "SDOpenAIClientTests",
            dependencies: ["SDOpenAIClient"]
        )
    ]
)
