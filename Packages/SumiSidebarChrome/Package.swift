// swift-tools-version: 5.9

import PackageDescription

// Sidebar chrome SPM peel (W8/R12): leaf Views move here incrementally.
// Depends on tokens + contracts only — must not import BrowserManager / TabManager.
let package = Package(
    name: "SumiSidebarChrome",
    platforms: [
        .macOS("15.5")
    ],
    products: [
        .library(name: "SumiSidebarChrome", targets: ["SumiSidebarChrome"]),
    ],
    dependencies: [
        .package(path: "../SumiChromeTokens"),
        .package(path: "../SumiChromeContracts"),
    ],
    targets: [
        .target(
            name: "SumiSidebarChrome",
            dependencies: [
                "SumiChromeTokens",
                "SumiChromeContracts",
            ]
        ),
    ]
)
