import XCTest

@testable import Sumi

final class SafariExtensionPermissionLifecycleDiagnosticsTests: XCTestCase {
    func testSanitizedURLDropsQueryFragmentAndPathDetails() throws {
        let url = try XCTUnwrap(
            URL(string: "https://account.example.test/login/callback?code=secret#frag")
        )

        let sanitized = SafariExtensionPermissionLifecycleDiagnostics.sanitizedURL(url)

        XCTAssertEqual(sanitized, "https://account.example.test/<path>")
        XCTAssertFalse(sanitized?.contains("secret") ?? true)
        XCTAssertFalse(sanitized?.contains("frag") ?? true)
        XCTAssertFalse(sanitized?.contains("callback") ?? true)
    }

    func testManifestSurfacesKeepExternallyConnectableSeparate() {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "content_scripts": [[
                "matches": ["https://site.example/*"],
                "js": ["content.js"],
                "all_frames": true,
            ]],
            "host_permissions": ["https://api.example/*"],
            "optional_host_permissions": ["https://vault.example/*"],
            "externally_connectable": [
                "matches": ["https://account.example/*"],
            ],
        ]

        let surfaces = SafariExtensionManifestAccessSurfaces.from(manifest: manifest)

        XCTAssertEqual(surfaces.contentScriptHosts, ["site.example"])
        XCTAssertEqual(surfaces.hostPermissionHosts, ["api.example"])
        XCTAssertEqual(surfaces.optionalPermissionHosts, ["vault.example"])
        XCTAssertEqual(surfaces.externallyConnectableHosts, ["account.example"])
        XCTAssertEqual(surfaces.surfaces(forHost: "account.example"), [.externallyConnectable])
        XCTAssertFalse(surfaces.surfaces(forHost: "account.example").contains(.contentScripts))
        XCTAssertFalse(surfaces.surfaces(forHost: "account.example").contains(.hostPermissions))
    }

    func testPolicySnapshotEncodesOnlyBucketsAndHosts() throws {
        let snapshot = SafariExtensionPolicySnapshot(
            extensionEnabled: true,
            extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                "com.example.extension"
            ),
            profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                UUID(uuidString: "00000000-0000-0000-0000-000000000001")
            ),
            tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                UUID(uuidString: "00000000-0000-0000-0000-000000000002")
            ),
            isPrivate: false,
            originHost: "account.example.test",
            decisionSource: .activeTabTemporaryGrant,
            declaredSurfaces: [.activeTab, .externallyConnectable],
            externallyConnectableReportedSeparately: true
        )

        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("account.example.test"))
        XCTAssertTrue(json.contains("activeTabTemporaryGrant"))
        XCTAssertFalse(json.contains("com.example.extension"))
        XCTAssertFalse(json.contains("00000000-0000-0000-0000-000000000001"))
        XCTAssertFalse(json.contains("00000000-0000-0000-0000-000000000002"))
    }

    func testMessageRouteKindsDistinguishWebExtensionDirections() {
        XCTAssertEqual(
            Set(SafariExtensionMessageRouteKind.allCases),
            [
                .popupToBackground,
                .webpageToBackgroundExternal,
                .backgroundToTabsSendMessage,
                .contentScriptToBackground,
                .nativeMessagingSend,
                .nativeMessagingConnect,
            ]
        )
    }

    func testReloadRebuildSnapshotDoesNotRequireFullURL() throws {
        let snapshot = SafariExtensionReloadRebuildSnapshot(
            triggerReason: "ExtensionManager.siteAccessPolicyChanged",
            profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket("profile-a"),
            tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket("tab-a"),
            host: SafariExtensionPermissionLifecycleDiagnostics.host(
                from: URL(string: "https://site.example/path?token=secret")
            ),
            userActionCaused: false,
            action: .destructiveRebuild
        )

        let json = try XCTUnwrap(
            String(data: JSONEncoder().encode(snapshot), encoding: .utf8)
        )

        XCTAssertTrue(json.contains("site.example"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("/path"))
    }
}
