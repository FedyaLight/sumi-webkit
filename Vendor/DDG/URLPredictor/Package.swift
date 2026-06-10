// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "URLPredictor",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(name: "URLPredictor", targets: ["URLPredictor"]),
    ],
    targets: [
        .target(name: "URLPredictor", dependencies: ["URLPredictorRust"]),
        .binaryTarget(
            name: "URLPredictorRust",
            path: "Binary/URLPredictorRust.xcframework"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ],
    swiftLanguageModes: [.v6]
)
