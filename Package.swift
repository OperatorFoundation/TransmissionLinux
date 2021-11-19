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
        .package(url: "https://github.com/OperatorFoundation/Chord", from: "0.0.15"),
        .package(url: "https://github.com/OperatorFoundation/Datable", from: "3.1.2"),
        .package(name: "Socket", url: "https://github.com/OperatorFoundation/BlueSocket", from: "1.1.0"),
        .package(url: "https://github.com/OperatorFoundation/Net", from: "1.0.0"),
        .package(url: "https://github.com/OperatorFoundation/Transport", from: "2.3.10"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TransmissionLinux",
            dependencies: [
                "Chord", "Socket", "Datable", "Transport", "Net",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "TransmissionLinuxTests",
            dependencies: ["TransmissionLinux", "Datable"]),
    ],
    swiftLanguageVersions: [.v5]
)
