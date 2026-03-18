// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SDOpenAIClientKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "SDOpenAIClient",
            targets: ["SDOpenAIClient"]
        )
    ],
    targets: [
        .target(
            name: "SDOpenAIClient",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SDOpenAIClientTests",
            dependencies: ["SDOpenAIClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
