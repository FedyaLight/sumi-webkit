// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "Common", targets: ["Common"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "PrivacyConfig", targets: ["PrivacyConfig"]),
        .library(name: "UserScript", targets: ["UserScript"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit.git", exact: "3.1.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts.git", exact: "14.2.0"),
        .package(path: "../URLPredictor"),
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "Persistence",
                "PrivacyConfig",
                "TrackerRadarKit",
                "Common",
                "UserScript",
                "ContentBlocking",
                "Navigation"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .copy("../../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Bookmarks",
            dependencies: [
                "Common",
                "Persistence",
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punycode", package: "PunycodeSwift"),
                .product(name: "URLPredictor", package: "URLPredictor"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Navigation",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("WILLPERFORMCLIENTREDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_IS_REDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_MAIN_FRAME_NAVIGATION_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_PERFORMANCE_ENABLED", .when(platforms: [.macOS])),
                .define("TERMINATE_WITH_REASON_ENABLED", .when(platforms: [.macOS])),
                .define("_SESSION_STATE_WITH_FILTER_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_AUTOPLAY_POLICY_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PrivacyConfig",
            dependencies: [
                "Common",
                "ContentBlocking",
                "Persistence",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "UserScript",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
