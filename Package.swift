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
            dependencies: ["MockerKit"]
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
