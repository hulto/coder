// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoderKit",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "CoderKit", targets: ["CoderKit"]),
    ],
    targets: [
        .target(
            name: "CoderKit",
            path: "Sources"
        ),
        .testTarget(
            name: "CoderKitTests",
            dependencies: ["CoderKit"],
            path: "Tests"
        ),
    ]
)
