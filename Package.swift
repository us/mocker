// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mocker",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "mocker", targets: ["Mocker"]),
        .library(name: "MockerKit", targets: ["MockerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        .package(url: "https://github.com/apple/containerization.git", branch: "main"),
        // Docker Engine API server (`mocker serve`) — unix-socket HTTP. swift-nio is already
        // resolved transitively (pinned 2.95.0 via containerization); declare it directly.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.95.0"),
    ],
    targets: [
        // Core library shared between CLI and GUI
        .target(
            name: "MockerKit",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),

        // CLI executable
        .executableTarget(
            name: "Mocker",
            dependencies: [
                "MockerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // Tests
        .testTarget(
            name: "MockerKitTests",
            dependencies: ["MockerKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MockerTests",
            dependencies: [
                "Mocker",
                "MockerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
