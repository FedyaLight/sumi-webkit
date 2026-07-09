// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SumiDomain",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiDomain", targets: ["SumiDomain"]),
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
