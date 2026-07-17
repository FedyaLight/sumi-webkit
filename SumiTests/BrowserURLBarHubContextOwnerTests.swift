import Combine
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLBarHubContextOwnerTests: XCTestCase {
    func testSecurityFooterPresentationUsesSystemLockSymbols() throws {
        let secureURL = try XCTUnwrap(URL(string: "https://example.test/path"))
        let insecureURL = try XCTUnwrap(URL(string: "http://example.test/path"))

        let secureState = SiteControlsSnapshot.resolve(url: secureURL, profile: nil).securityState
        let insecureState = SiteControlsSnapshot.resolve(url: insecureURL, profile: nil).securityState

        XCTAssertEqual(secureState, .secure)
        XCTAssertEqual(secureState.footerTitle, "Secure")
        XCTAssertNil(secureState.chromeIconName)
        XCTAssertEqual(secureState.fallbackSystemName, "lock.fill")
        XCTAssertFalse(secureState.isFooterStruckThrough)

        XCTAssertEqual(insecureState, .notSecure)
        XCTAssertEqual(insecureState.footerTitle, "Secure")
        XCTAssertNil(insecureState.chromeIconName)
        XCTAssertEqual(insecureState.fallbackSystemName, "lock.open.fill")
        XCTAssertTrue(insecureState.isFooterStruckThrough)
    }

    func testLiveContextUsesComposedBrowserRoles() {
        let browserManager = BrowserManager()
        let context = browserManager.urlBarBundle.contextOwner.urlBarHubContext
        let resolvedSnapshot = SiteControlsSnapshot.resolve(
            url: nil,
            profile: nil
        )

        XCTAssertIdentical(context.bookmarkManager, browserManager.bookmarkManager)
        XCTAssertIdentical(context.adblockZapperStore, browserManager.adblockZapperStore)
        XCTAssertIdentical(context.permission.popupStore, browserManager.permissionRuntime.blockedPopupStore)
        XCTAssertIdentical(
            context.permissionDependencies.blockedPopupStore,
            browserManager.permissionRuntime.blockedPopupStore
        )
        XCTAssertEqual(
            context.extensionActions.toolbarPresentationSnapshot(nil),
            .empty
        )
        XCTAssertEqual(context.siteControlsSnapshot(nil, nil, false, false), resolvedSnapshot)
    }

    func testLiveContextWithBoostsDisabledDoesNotLoadBoostStore() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = URLHubBoostRuntimeProbe()
        let boostsModule = SumiBoostsModule(
            moduleRegistry: registry,
            storeFactory: {
                probe.storeCount += 1
                return SumiBoostStore()
            }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            boostsModule: boostsModule
        )
        let context = browserManager.urlBarBundle.contextOwner.urlBarHubContext
        let url = try XCTUnwrap(URL(string: "https://example.test/path"))
        var boostRefreshCount = 0
        let cancellable = context.boostChanges.sink {
            boostRefreshCount += 1
        }
        defer { cancellable.cancel() }

        XCTAssertFalse(context.canBoost(url))
        XCTAssertTrue(context.changedBoosts(url, UUID()).isEmpty)
        XCTAssertNil(context.activeBoostId(url, UUID()))
        XCTAssertEqual(probe.storeCount, 0)

        boostsModule.setEnabled(true)

        XCTAssertEqual(boostRefreshCount, 1)
        XCTAssertEqual(probe.storeCount, 0)
    }
}

private final class URLHubBoostRuntimeProbe {
    var storeCount = 0
}
