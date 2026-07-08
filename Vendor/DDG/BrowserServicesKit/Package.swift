// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(name: "Common", targets: ["Common"]),
        .library(name: "Navigation", targets: ["Navigation"]),
    ],
    targets: [
        .target(
            name: "Common",
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
    ],
    cxxLanguageStandard: .cxx11
)
