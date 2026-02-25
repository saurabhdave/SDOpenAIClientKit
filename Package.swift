// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "SDOpenAIClientKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SDOpenAIClientKit",
            targets: ["SDOpenAIClientKit"]
        )
    ],
    targets: [
        .target(
            name: "SDOpenAIClientKit"
        ),
        .testTarget(
            name: "SDOpenAIClientKitTests",
            dependencies: ["SDOpenAIClientKit"]
        )
    ]
)
