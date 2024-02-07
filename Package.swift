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
        .package(url: "https://github.com/OperatorFoundation/BlueSocket", branch: "release"),
        .package(url: "https://github.com/OperatorFoundation/Chord", branch: "0.1.1"),
        .package(url: "https://github.com/OperatorFoundation/Datable", from: "4.0.0"),
        .package(url: "https://github.com/OperatorFoundation/Net", branch: "release"),
        .package(url: "https://github.com/OperatorFoundation/Straw", branch: "release"),
        .package(url: "https://github.com/OperatorFoundation/SwiftHexTools", from: "1.2.6"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionBase", branch: "release"),
        .package(url: "https://github.com/OperatorFoundation/TransmissionTypes", branch: "release"),
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
