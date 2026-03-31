// swift-tools-version: 5.09
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PluginSpector",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "PluginSpector",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]),
    ]
)
