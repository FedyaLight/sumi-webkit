// swift-tools-version: 5.9

import PackageDescription

// Policy: WebKit + Foundation + AppKit are allowed. SwiftUI is forbidden.
// Combine / OSLog / Observation are OK. Must not type-edge into app-target
// Tab / BrowserWindowState / BrowserManager.
let package = Package(
    name: "SumiWebRuntime",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        // Dynamic so host-based SumiTests do not statically embed a second
        // copy of the module (duplicate class metadata breaks session-handle
        // identity across the app/test boundary).
        .library(name: "SumiWebRuntime", type: .dynamic, targets: ["SumiWebRuntime"]),
    ],
    targets: [
        .target(name: "SumiWebRuntime"),
        .testTarget(
            name: "SumiWebRuntimeTests",
            dependencies: ["SumiWebRuntime"]
        ),
    ]
)
