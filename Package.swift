// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransmissionLinux",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TransmissionLinux",
            targets: ["TransmissionLinux"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2"),

        .package(name: "Socket", url: "https://github.com/OperatorFoundation/BlueSocket", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Chord", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Datable", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/Net", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools.git", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionBase", branch: "main"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionTypes", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TransmissionLinux",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),

                "Chord",
                "Datable",
                "Net",
                "Socket",
                "SwiftHexTools",
                "TransmissionBase",
                "TransmissionTypes",
            ]
        ),
        .testTarget(
            name: "TransmissionLinuxTests",
            dependencies: [
                "Datable",
                "Socket",
                "TransmissionLinux",
          ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
