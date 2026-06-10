// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SUI-InputModifier",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "InputViewKit", targets: ["InputViewKit"])
    ],
    targets: [
        .target(name: "InputViewKit"),
        .testTarget(name: "InputViewKitTests", dependencies: ["InputViewKit"])
    ]
)
