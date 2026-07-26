// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebAppFeature",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WebAppFeature", targets: ["WebAppFeature"]),
    ],
    targets: [
        .target(
            name: "WebAppFeature",
            path: "Sources"
        ),
        .testTarget(
            name: "WebAppFeatureTests",
            dependencies: ["WebAppFeature"],
            path: "Tests"
        ),
    ]
)
