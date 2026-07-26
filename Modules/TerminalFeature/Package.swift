// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalFeature",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TerminalFeature", targets: ["TerminalFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "TerminalFeature",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "TerminalFeatureTests",
            dependencies: ["TerminalFeature"],
            path: "Tests"
        ),
    ]
)
