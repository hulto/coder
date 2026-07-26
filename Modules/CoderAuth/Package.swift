// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoderAuth",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CoderAuth", targets: ["CoderAuth"]),
    ],
    targets: [
        .target(
            name: "CoderAuth",
            path: "Sources"
        ),
        .testTarget(
            name: "CoderAuthTests",
            dependencies: ["CoderAuth"],
            path: "Tests"
        ),
    ]
)
