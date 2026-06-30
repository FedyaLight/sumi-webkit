import SwiftData
import XCTest

@testable import Sumi

final class SafariExtensionSessionDiagnosticsTests: XCTestCase {
    @MainActor
    func testLogIfDiagnosticsEnabledDoesNotBuildWhenVerboseLoggingIsDisabled() async throws {
        try XCTSkipIf(
            RuntimeDiagnostics.isVerboseEnabled,
            "This assertion only holds when verbose runtime logging is disabled."
        )

        var built = false
        await SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled {
            built = true
            return SafariExtensionSessionDiagnostic(
                recordedAt: Date(),
                extensionId: "example-extension",
                phase: .opened,
                safariRuntimeLoadSource: nil,
                popupUsesOriginalAppex: false,
                extensionContextLoaded: false,
                popupWebViewPresent: false,
                isPopupActive: false,
                activeTabStore: nil,
                extensionControllerDefaultStore: nil,
                extensionPageConfigurationStore: nil,
                popupWebViewStore: nil,
                cookieDomainCounts: [],
                permissionBucketSummary: "notBuilt",
                inferredFailureBucket: .unknown,
                note: "not built"
            )
        }

        XCTAssertFalse(built)
    }

    @MainActor
    func testBuildUsesInjectedRuntimeWithoutBrowserManager() async throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Diagnostics Runtime")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: nil
        )
        let runtime = SafariExtensionSessionDiagnosticsRuntime(
            currentTab: { nil },
            currentProfile: { profile },
            profile: { profileId in
                profileId == profile.id ? profile : nil
            },
            activeTabStore: { _ in nil }
        )

        let diagnostic = await SafariExtensionSessionDiagnosticsBuilder.build(
            extensionId: "example-extension",
            phase: .opened,
            extensionManager: manager,
            runtime: runtime
        )

        XCTAssertNil(manager.browserManager)
        XCTAssertFalse(diagnostic.extensionContextLoaded)
        XCTAssertNil(diagnostic.activeTabStore)
        XCTAssertNil(diagnostic.extensionControllerDefaultStore)
        XCTAssertNil(diagnostic.extensionPageConfigurationStore)
    }

    func testFailureBucketIncludesCookieStoreNotShared() {
        XCTAssertTrue(
            SafariExtensionSessionFailureBucket.allCases.contains(.cookieStoreNotShared)
        )
    }

    func testDiagnosticEncodesWithoutSensitiveFields() throws {
        let diagnostic = SafariExtensionSessionDiagnostic(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            extensionId: "example-extension",
            phase: .opened,
            safariRuntimeLoadSource: .originalAppexBundle,
            popupUsesOriginalAppex: true,
            extensionContextLoaded: true,
            popupWebViewPresent: true,
            isPopupActive: true,
            activeTabStore: SafariExtensionWebsiteDataStoreSnapshot(
                identifier: "PROFILE-ID",
                isPersistent: true,
                matchesProfileStore: true,
                matchesExtensionControllerDefaultStore: true,
                matchesActiveTabStore: true
            ),
            extensionControllerDefaultStore: nil,
            extensionPageConfigurationStore: nil,
            popupWebViewStore: nil,
            cookieDomainCounts: [
                SafariExtensionCookieDomainCount(domain: "raindrop.io", count: 2),
            ],
            permissionBucketSummary: "grantedHostPatterns=1 requestedPermissions=3",
            inferredFailureBucket: .none,
            note: "stores aligned"
        )

        let data = try JSONEncoder().encode(diagnostic)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("cookieDomainCounts"))
        XCTAssertTrue(json.contains("\"count\":2"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("password"))
    }
}
