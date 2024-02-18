// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TransmissionLinux",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "TransmissionLinux",
            targets: ["TransmissionLinux"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/OperatorFoundation/BlueSocket", from: "1.1.2"),
        .package(url: "https://github.com/OperatorFoundation/Chord", from: "0.1.4"),
        .package(url: "https://github.com/OperatorFoundation/Datable", from: "4.0.0"),
        .package(url: "https://github.com/OperatorFoundation/Net", from: "0.0.10"),
        .package(url: "https://github.com/OperatorFoundation/Straw", from: "1.0.1"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools", from: "1.2.6"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionBase", from: "1.0.1"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionTypes", from: "0.0.2"),
    ],
    targets: [
        .target(
            name: "TransmissionLinux",
            dependencies: [
                "Chord",
                "Datable",
                "Net",
                "Straw",
                "SwiftHexTools",
                "TransmissionBase",
                "TransmissionTypes",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Socket", package: "BlueSocket")]),
        
        .testTarget(
            name: "TransmissionLinuxTests",
            dependencies: [
                "Chord",
                "Datable",
                "Net",
                "SwiftHexTools",
                "TransmissionBase",
                "TransmissionTypes",
                "TransmissionLinux"]),
    ],
    swiftLanguageVersions: [.v5]
)
