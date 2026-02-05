// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "making_music",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MakingMusicCore",
            targets: ["MakingMusicCore"]
        ),
        .executable(
            name: "making_music",
            targets: ["making_music"]
        ),
        .executable(
            name: "making_music_selftest",
            targets: ["making_music_selftest"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MakingMusicCore"
        ),
        .executableTarget(
            name: "making_music",
            dependencies: ["MakingMusicCore"]
        ),
        .executableTarget(
            name: "making_music_selftest",
            dependencies: ["MakingMusicCore"]
        ),
    ]
)
