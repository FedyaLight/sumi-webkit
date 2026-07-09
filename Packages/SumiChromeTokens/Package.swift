// swift-tools-version: 5.9

import PackageDescription

// Policy: Foundation + CoreGraphics only. No SwiftUI / AppKit / WebKit.
// Shared chrome layout metrics for Sidebar and FloatingBar packages.
// SwiftUI Color recipes remain in the Sumi app target (`ChromeThemeTokens`).
let package = Package(
    name: "SumiChromeTokens",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiChromeTokens", targets: ["SumiChromeTokens"]),
    ],
    targets: [
        .target(
            name: "SumiChromeTokens"
        ),
    ]
)
