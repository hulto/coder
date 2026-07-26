// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoderUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CoderUI", targets: ["CoderUI"]),
    ],
    dependencies: [
        .package(name: "CoderAuth", path: "../CoderAuth"),
    ],
    targets: [
        .target(
            name: "CoderUI",
            dependencies: [
                .product(name: "CoderAuth", package: "CoderAuth"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "CoderUITests",
            dependencies: ["CoderUI"],
            path: "Tests/CoderUITests"
        ),
    ]
)
