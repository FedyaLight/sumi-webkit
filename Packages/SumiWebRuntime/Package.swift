// swift-tools-version: 5.9

import PackageDescription

// Policy: WebKit + Foundation + AppKit are allowed. SwiftUI is forbidden.
// Combine / OSLog / Observation are OK. Depends on SumiDomain; must not
// type-edge into app-target Tab / BrowserWindowState / BrowserManager.
let package = Package(
    name: "SumiWebRuntime",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiWebRuntime", targets: ["SumiWebRuntime"]),
    ],
    dependencies: [
        .package(path: "../SumiDomain"),
    ],
    targets: [
        .target(
            name: "SumiWebRuntime",
            dependencies: ["SumiDomain"]
        ),
        .testTarget(
            name: "SumiWebRuntimeTests",
            dependencies: ["SumiWebRuntime"]
        ),
    ]
)
