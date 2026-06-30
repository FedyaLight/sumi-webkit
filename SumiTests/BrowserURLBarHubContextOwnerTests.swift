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
            ensureActionSurfaceMetadataLoadedIfNeeded: {
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
        XCTAssertIdentical(context.extensionSurfaceStore, browserManager.extensionSurfaceStore)
        XCTAssertIdentical(context.permission.popupStore, browserManager.permissionRuntime.blockedPopupStore)
        XCTAssertIdentical(
            context.permissionDependencies.blockedPopupStore,
            browserManager.permissionRuntime.blockedPopupStore
        )
        XCTAssertEqual(context.extensionActions.orderedPinnedToolbarSlotCount([]), 7)
        XCTAssertTrue(context.extensionActions.isPinnedToToolbar("pinned-extension"))
        XCTAssertTrue(context.extensionActions.sumiScriptsManagerEnabled())
        XCTAssertEqual(context.siteControlsSnapshot(nil, nil, false, false), resolvedSnapshot)

        context.extensionActions.ensureActionSurfaceMetadataLoadedIfNeeded()

        XCTAssertEqual(metadataLoadCount, 1)
    }
}
