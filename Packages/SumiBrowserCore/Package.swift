// swift-tools-version: 5.9

import PackageDescription

// Tab-structure event bus, UUID-safe ports, and store protocols peeled from the
// Sumi app target. Depends on SumiDomain. SwiftUI is forbidden.
// Combine is used via the Apple SDK (no package dependency).
let package = Package(
    name: "SumiBrowserCore",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiBrowserCore", targets: ["SumiBrowserCore"]),
    ],
    dependencies: [
        .package(path: "../SumiDomain"),
    ],
    targets: [
        .target(
            name: "SumiBrowserCore",
            dependencies: [
                "SumiDomain",
            ]
        ),
    ]
)
