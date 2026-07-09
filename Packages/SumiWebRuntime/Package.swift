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
        // Dynamic so host-based SumiTests do not statically embed a second
        // copy of the module (duplicate class metadata breaks TabWebViewSession
        // field access across the app/test boundary).
        .library(name: "SumiWebRuntime", type: .dynamic, targets: ["SumiWebRuntime"]),
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
