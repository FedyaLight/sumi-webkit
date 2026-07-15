import XCTest

@testable import Sumi

@MainActor
final class TabTransientTabRegistryOwnerTests: XCTestCase {
    func testLiveShortcutResidenceStoreRetainsReceiptsThroughRemoval() {
        let store = LiveShortcutTabResidenceStore()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstPinId = UUID()
        let secondPinId = UUID()
        let keptSpaceId = UUID()
        let removedSpaceId = UUID()
        let keptTab = makeTab(spaceId: keptSpaceId)
        let removedTab = makeTab(spaceId: removedSpaceId)

        let keptPage = LiveShortcutPresentationPageReceipt(
            windowID: firstWindowId,
            spaceID: keptSpaceId,
            profileID: nil
        )
        let removedPage = LiveShortcutPresentationPageReceipt(
            windowID: secondWindowId,
            spaceID: removedSpaceId,
            profileID: nil
        )
        XCTAssertNotNil(store.register(
            keptTab,
            for: firstPinId,
            in: firstWindowId,
            presentationPage: keptPage
        ))
        XCTAssertNotNil(store.register(
            removedTab,
            for: secondPinId,
            in: secondWindowId,
            presentationPage: removedPage
        ))

        let removed = store.removeAll {
            $0.presentationPage.page.spaceID == removedSpaceId
        }

        XCTAssertIdentical(
            store.tabsByWindow[firstWindowId]?[firstPinId],
            keptTab
        )
        XCTAssertEqual(removed.map(\.presentationPage), [removedPage])
        XCTAssertNil(store.tabsByWindow[secondWindowId])

        let removal = store.remove(tabId: keptTab.id)

        XCTAssertEqual(removal?.windowId, firstWindowId)
        XCTAssertEqual(removal?.pinId, firstPinId)
        XCTAssertIdentical(removal?.tab, keptTab)
        XCTAssertEqual(removal?.presentationPage, keptPage)
        XCTAssertTrue(store.tabsByWindow.isEmpty)
    }

    func testTransientExtensionTabsRegisterRemoveAndPromote() {
        let owner = TabTransientTabRegistryOwner()
        let tab = makeTab()

        owner.registerTransientExtensionTab(tab)

        XCTAssertTrue(owner.isTransientExtensionTab(tab))
        XCTAssertIdentical(owner.removeTransientExtensionTab(id: tab.id), tab)
        XCTAssertFalse(owner.isTransientExtensionTab(tab))

        owner.registerTransientExtensionTab(tab)
        XCTAssertTrue(owner.promoteTransientExtensionTab(tab))
        XCTAssertFalse(owner.isTransientExtensionTab(tab))
        XCTAssertFalse(owner.promoteTransientExtensionTab(tab))
    }

    func testAuxiliaryMiniWindowTabsRegisterAndRemove() {
        let owner = TabTransientTabRegistryOwner()
        let tab = makeTab()

        owner.registerAuxiliaryMiniWindowTab(tab)

        XCTAssertTrue(owner.isAuxiliaryMiniWindowTab(tab))
        XCTAssertIdentical(owner.auxiliaryMiniWindowTab(for: tab.id), tab)

        owner.removeAuxiliaryMiniWindowTab(tab)

        XCTAssertFalse(owner.isAuxiliaryMiniWindowTab(tab))
        XCTAssertNil(owner.auxiliaryMiniWindowTab(for: tab.id))
    }

    private func makeTab(spaceId: UUID? = nil) -> Tab {
        Tab(spaceId: spaceId, loadsCachedFaviconOnInit: false)
    }
}
