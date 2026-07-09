// swift-tools-version: 5.9

import PackageDescription

// Policy: Foundation-only chrome commanding contracts.
// Chrome Views (SumiSidebarChrome / SumiFloatingBarChrome) depend on these
// protocols instead of app-target BrowserManager / TabManager types.
let package = Package(
    name: "SumiChromeContracts",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiChromeContracts", targets: ["SumiChromeContracts"]),
    ],
    targets: [
        .target(
            name: "SumiChromeContracts"
        ),
    ]
)
