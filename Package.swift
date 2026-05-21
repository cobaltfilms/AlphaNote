// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AlphaNote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AlphaNote",
            targets: ["AlphaNote"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "AlphaNote",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OrderedCollections", package: "swift-collections")
            ],
            path: "Sources/AlphaNote",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AlphaNoteTests",
            dependencies: ["AlphaNote"],
            path: "Tests/AlphaNoteTests"
        )
    ]
)