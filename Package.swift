// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LaunchDeck",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LaunchDeckCore", targets: ["LaunchDeckCore"]),
    ],
    targets: [
        .target(name: "LaunchDeckCore", path: "LaunchDeck/Core"),
        .testTarget(name: "LaunchDeckCoreTests", dependencies: ["LaunchDeckCore"]),
    ]
)
