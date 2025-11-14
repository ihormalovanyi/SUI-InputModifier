// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SUI-InputModifier",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "SUI-InputModifier",
            targets: ["SUI-InputModifier"]
        ),
    ],
    targets: [
        .target(
            name: "SUI-InputModifier"
        ),
    ]
)
