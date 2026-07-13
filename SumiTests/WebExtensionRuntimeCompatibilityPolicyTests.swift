import XCTest

@testable import Sumi

final class WebExtensionRuntimeCompatibilityPolicyTests: XCTestCase {
    func testNonWebKitManifestDoesNotDisableLegacyInjectionAPIs() {
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
                    "browser.tabs.executeScript",
                    "browser.tabs.insertCSS",
                ],
                "Unexpected compatibility policy for \(target)"
            )
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
