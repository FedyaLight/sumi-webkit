import XCTest

@testable import Sumi

final class WebExtensionRuntimeCompatibilityPolicyTests: XCTestCase {
    func testNonWebKitManifestDoesNotOverrideNativeAPIs() {
        XCTAssertEqual(
            WebExtensionRuntimeCompatibilityPolicy.unsupportedAPIs(
                for: ["manifest_version": 3]
            ),
            []
        )
    }

    func testEverySupportedWebKitTargetSpellingUsesTheSamePolicy() {
        for target in ["safari", "webkit", "WebKit"] {
            let unsupported = WebExtensionRuntimeCompatibilityPolicy
                .unsupportedAPIs(
                    for: [
                        "browser_specific_settings": [target: [:]],
                    ]
                )
            XCTAssertEqual(
                unsupported,
                [
                    "browser.contentScripts.register",
                ],
                "Unexpected compatibility policy for \(target)"
            )
        }
    }

    func testWebKitOwnsManifestAwareLegacyTabsAPIAvailability() {
        for manifestVersion in [2, 3] {
            let unsupported = WebExtensionRuntimeCompatibilityPolicy
                .unsupportedAPIs(
                    for: [
                        "manifest_version": manifestVersion,
                        "browser_specific_settings": ["safari": [:]],
                    ]
                )

            XCTAssertFalse(unsupported.contains("browser.tabs.executeScript"))
            XCTAssertFalse(unsupported.contains("browser.tabs.insertCSS"))
            XCTAssertFalse(unsupported.contains("browser.tabs.removeCSS"))
        }
    }

    func testNativeMessagingClassificationUsesRequiredPermissionsOnly() {
        XCTAssertTrue(
            WebExtensionRuntimeCompatibilityPolicy.declaresNativeMessaging(
                ["permissions": ["storage", "nativeMessaging"]]
            )
        )
        XCTAssertFalse(
            WebExtensionRuntimeCompatibilityPolicy.declaresNativeMessaging(
                ["optional_permissions": ["nativeMessaging"]]
            )
        )
    }
}
