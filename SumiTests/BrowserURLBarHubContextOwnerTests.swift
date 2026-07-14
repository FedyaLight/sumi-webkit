import Combine
import SwiftUI
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

    func testLiveContextUsesBrowserManagerStoresAndInjectedExtensionActions() {
        let browserManager = BrowserManager()
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(browserManager: browserManager)
        var metadataLoadCount = 0
        let extensionActions = URLBarExtensionActionContext(
            moduleEnabledChanges: Just(true).eraseToAnyPublisher(),
            toolbarPresentationSnapshot: { _ in .empty },
            toolbarPresentationSnapshots: { _ in
                Empty().eraseToAnyPublisher()
            },
            compactStrip: { _, _, _ in AnyView(EmptyView()) },
            hubTiles: { _, _, _ in AnyView(EmptyView()) },
            ensureActionMetadataLoadedIfNeeded: {
                metadataLoadCount += 1
            }
        )
        let resolvedSnapshot = SiteControlsSnapshot.resolve(url: nil, profile: nil)
        let owner = BrowserURLBarHubContextOwner(
            browserManager: browserManager,
            permissionContextOwner: permissionContextOwner,
            extensionActionContext: { extensionActions },
            siteControlsSnapshot: { _, _, _, _ in resolvedSnapshot },
            settingsNavigation: browserManager.urlBarBundle.settingsNavigation
        )

        let context = owner.context

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

        context.extensionActions.ensureActionMetadataLoadedIfNeeded()

        XCTAssertEqual(metadataLoadCount, 1)
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
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(browserManager: browserManager)
        let extensionActions = URLBarExtensionActionContext(
            moduleEnabledChanges: Just(false).eraseToAnyPublisher(),
            toolbarPresentationSnapshot: { _ in .empty },
            toolbarPresentationSnapshots: { _ in
                Empty().eraseToAnyPublisher()
            },
            compactStrip: { _, _, _ in AnyView(EmptyView()) },
            hubTiles: { _, _, _ in AnyView(EmptyView()) },
            ensureActionMetadataLoadedIfNeeded: {}
        )
        let owner = BrowserURLBarHubContextOwner(
            browserManager: browserManager,
            permissionContextOwner: permissionContextOwner,
            extensionActionContext: { extensionActions },
            siteControlsSnapshot: { url, profile, _, _ in
                SiteControlsSnapshot.resolve(url: url, profile: profile)
            },
            settingsNavigation: browserManager.urlBarBundle.settingsNavigation
        )
        let context = owner.context
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
