// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "evidence",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Evidence",
            targets: ["Evidence"]
        ),
        .executable(
            name: "evidence",
            targets: ["EvidenceCLI"]
        )
    ],
    targets: [
        .target(
            name: "Evidence"
        ),
        .executableTarget(
            name: "EvidenceCLI",
            dependencies: []
        ),
        .testTarget(
            name: "EvidenceTests",
            dependencies: ["Evidence"]
        )
    ]
)
