import Combine
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLBarHubContextOwnerTests: XCTestCase {
    func testLiveContextUsesBrowserManagerStoresAndInjectedExtensionActions() {
        let browserManager = BrowserManager()
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: browserManager)
        )
        var metadataLoadCount = 0
        let extensionActions = URLBarExtensionActionContext(
            orderedPinnedToolbarSlotCount: { _ in 7 },
            compactStrip: { _, _ in AnyView(EmptyView()) },
            hubTiles: { _, _ in AnyView(EmptyView()) },
            ensureActionMetadataLoadedIfNeeded: {
                metadataLoadCount += 1
            },
            isPinnedToToolbar: { extensionId in
                extensionId == "pinned-extension"
            },
            sumiScriptsManagerEnabled: {
                true
            }
        )
        let resolvedSnapshot = SiteControlsSnapshot.resolve(url: nil, profile: nil)
        let owner = BrowserURLBarHubContextOwner(
            dependencies: .live(
                browserManager: browserManager,
                permissionContextOwner: permissionContextOwner,
                extensionActionContext: { extensionActions },
                siteControlsSnapshot: { _, _, _, _ in resolvedSnapshot }
            )
        )

        let context = owner.context

        XCTAssertIdentical(context.bookmarkManager, browserManager.bookmarkManager)
        XCTAssertIdentical(context.extensionSurfaceStore, browserManager.extensionsModule.surfaceStore)
        XCTAssertIdentical(context.permission.popupStore, browserManager.permissionRuntime.blockedPopupStore)
        XCTAssertIdentical(
            context.permissionDependencies.blockedPopupStore,
            browserManager.permissionRuntime.blockedPopupStore
        )
        XCTAssertEqual(context.extensionActions.orderedPinnedToolbarSlotCount([]), 7)
        XCTAssertTrue(context.extensionActions.isPinnedToToolbar("pinned-extension"))
        XCTAssertTrue(context.extensionActions.sumiScriptsManagerEnabled())
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
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: browserManager)
        )
        let extensionActions = URLBarExtensionActionContext(
            orderedPinnedToolbarSlotCount: { _ in 0 },
            compactStrip: { _, _ in AnyView(EmptyView()) },
            hubTiles: { _, _ in AnyView(EmptyView()) },
            ensureActionMetadataLoadedIfNeeded: {},
            isPinnedToToolbar: { _ in false },
            sumiScriptsManagerEnabled: { false }
        )
        let owner = BrowserURLBarHubContextOwner(
            dependencies: .live(
                browserManager: browserManager,
                permissionContextOwner: permissionContextOwner,
                extensionActionContext: { extensionActions },
                siteControlsSnapshot: { url, profile, _, _ in
                    SiteControlsSnapshot.resolve(url: url, profile: profile)
                }
            )
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
