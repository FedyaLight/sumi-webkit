import XCTest

@testable import Sumi

@MainActor
final class TabTransientTabRegistryOwnerTests: XCTestCase {
    func testTransientShortcutTabsCanBePrunedBySpaceAndRemovedByTabId() {
        let owner = TabTransientTabRegistryOwner()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstPinId = UUID()
        let secondPinId = UUID()
        let keptSpaceId = UUID()
        let removedSpaceId = UUID()
        let keptTab = makeTab(spaceId: keptSpaceId)
        let removedTab = makeTab(spaceId: removedSpaceId)

        owner.updateTransientShortcutTabsByWindow { tabsByWindow in
            tabsByWindow[firstWindowId] = [firstPinId: keptTab]
            tabsByWindow[secondWindowId] = [secondPinId: removedTab]
        }

        owner.removeTransientShortcutTabs(inSpace: removedSpaceId)

        XCTAssertIdentical(
            owner.transientShortcutTabsByWindow[firstWindowId]?[firstPinId],
            keptTab
        )
        XCTAssertNil(owner.transientShortcutTabsByWindow[secondWindowId])

        let removal = owner.removeTransientShortcutTab(tabId: keptTab.id)

        XCTAssertEqual(removal?.windowId, firstWindowId)
        XCTAssertEqual(removal?.pinId, firstPinId)
        XCTAssertIdentical(removal?.tab, keptTab)
        XCTAssertTrue(owner.transientShortcutTabsByWindow.isEmpty)
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
