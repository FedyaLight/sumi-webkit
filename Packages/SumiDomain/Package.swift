// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SumiDomain",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        // Dynamic so the app and its hosted test bundle share one runtime
        // image instead of embedding duplicate Objective-C class metadata.
        .library(
            name: "SumiDomain",
            type: .dynamic,
            targets: ["SumiDomain"]
        ),
    ],
    targets: [
        .target(
            name: "SumiDomain",
            resources: [
                .copy("Resources/public_suffix_list.dat"),
            ]
        ),
        .testTarget(
            name: "SumiDomainTests",
            dependencies: ["SumiDomain"]
        ),
    ]
)
