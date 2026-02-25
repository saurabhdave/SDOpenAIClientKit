// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "SDOpenAIClientKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
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
