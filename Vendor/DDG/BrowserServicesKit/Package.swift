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
        .library(name: "History", targets: ["History"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "PrivacyConfig", targets: ["PrivacyConfig"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "WKAbstractions", targets: ["WKAbstractions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "19.0.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit.git", exact: "3.1.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts.git", exact: "14.2.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", exact: "4.13.5"),
        .package(path: "../URLPredictor"),
    ],
    targets: [
        .binaryTarget(
            name: "BloomFilter",
            url: "https://github.com/duckduckgo/bloom_cpp/releases/download/3.0.4/BloomFilter.xcframework.zip",
            checksum: "137fefd4a0ccf79560d7071d3387475806b84a7719785a6f80ea9c1d838c7d6b"
        ),
        .binaryTarget(
            name: "GRDB",
            url: "https://github.com/duckduckgo/GRDB.swift/releases/download/2.4.2/GRDB.xcframework.zip",
            checksum: "5380265b0e70f0ed28eb1e12640eb6cde5e4bfd39893c86b31f8d17126887174"
        ),
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                .product(name: "Autofill", package: "duckduckgo-autofill"),
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "Persistence",
                "PrivacyConfig",
                "TrackerRadarKit",
                "BloomFilterWrapper",
                "Common",
                "UserScript",
                "ContentBlocking",
                "SecureStorage",
                "Subscription",
                "PixelKit",
                "Navigation"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .process("SmarterEncryption/Store/HTTPSUpgrade.xcdatamodeld"),
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
            name: "History",
            dependencies: [
                "Persistence",
                "Common"
            ],
            resources: [
                .process("CoreData/BrowsingHistory.xcdatamodeld")
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
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
                .define("_SESSION_STATE_WITH_FILTER_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_AUTOPLAY_POLICY_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "Networking",
            dependencies: [
                .product(name: "JWTKit", package: "jwt-kit"),
                "Common"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
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
            name: "PixelKit",
            dependencies: [
                "Common",
                "Persistence"
            ],
            exclude: [
                "README.md"
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
            name: "SecureStorage",
            dependencies: [
                "Common",
                "PixelKit",
                "GRDB",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Subscription",
            dependencies: [
                "Common",
                "Networking",
                "UserScript",
                "PixelKit",
                "Persistence",
                "SecureStorage"
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
        .target(
            name: "BloomFilterObjC",
            dependencies: [
                "BloomFilter"
            ]
        ),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilterObjC",
            ]
        ),
        .target(
            name: "WKAbstractions",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
