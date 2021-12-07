// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransmissionLinux",
    platforms: [.macOS(.v10_15)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TransmissionLinux",
            targets: ["TransmissionLinux"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionTypes", from: "0.0.1"),
        .package(url: "https://github.com/OperatorFoundation/Chord", from: "0.0.15"),
        .package(url: "https://github.com/OperatorFoundation/Datable", from: "3.1.4"),
        .package(name: "Socket", url: "https://github.com/Kitura/BlueSocket", from: "2.0.2"),
        .package(url: "https://github.com/OperatorFoundation/Net", from: "0.0.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools.git", from: "1.2.5")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TransmissionLinux",
            dependencies: [
                "TransmissionTypes", "Chord", "Socket", "Datable", "Net", "SwiftHexTools",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "TransmissionLinuxTests",
            dependencies: ["TransmissionLinux", "Datable"]),
    ],
    swiftLanguageVersions: [.v5]
)
