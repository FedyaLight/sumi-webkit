// swift-tools-version: 5.9

import PackageDescription

// Scaffold for peeling FloatingBar chrome into an SPM package.
// Depends on tokens + contracts only — must not import BrowserManager / TabManager.
let package = Package(
    name: "SumiFloatingBarChrome",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiFloatingBarChrome", targets: ["SumiFloatingBarChrome"]),
    ],
    dependencies: [
        .package(path: "../SumiChromeTokens"),
        .package(path: "../SumiChromeContracts"),
    ],
    targets: [
        .target(
            name: "SumiFloatingBarChrome",
            dependencies: [
                "SumiChromeTokens",
                "SumiChromeContracts",
            ]
        ),
    ]
)
