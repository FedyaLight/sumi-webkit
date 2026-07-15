import SumiDomain
import XCTest

final class SumiDomainStateTests: XCTestCase {
    func testTabPlacementStateHasValueSemantics() {
        var original = TabPlacementState()
        original.spaceId = UUID()

        var copy = original
        copy.isPinned = true

        XCTAssertFalse(original.isPinned)
        XCTAssertTrue(copy.isPinned)
    }

    func testTabSurfaceStateAppliesNativeSurfaceAndPopupPolicy() {
        let settingsURL = SumiSurface.settingsSurfaceURL(paneQuery: "general")
        let webURL = URL(string: "https://example.com")!
        var state = TabSurfaceState()

        XCTAssertTrue(state.representsSumiNativeSurface(for: settingsURL))
        XCTAssertFalse(state.requiresPrimaryWebView(for: settingsURL))
        XCTAssertTrue(state.requiresPrimaryWebView(for: webURL))
        XCTAssertTrue(state.usesChromeThemedTemplateFavicon(
            for: settingsURL,
            faviconIsTemplateGlobePlaceholder: false
        ))

        state.isPopupHost = true
        XCTAssertFalse(state.representsSumiNativeSurface(for: settingsURL))
        XCTAssertTrue(state.requiresPrimaryWebView(for: settingsURL))
        XCTAssertFalse(state.usesChromeThemedTemplateFavicon(
            for: settingsURL,
            faviconIsTemplateGlobePlaceholder: true
        ))
    }

    func testWindowSelectionHistoryMaintainsUniqueBoundedMRUOrder() {
        let spaceID = UUID()
        let tabIDs = (0..<25).map { _ in UUID() }
        var history = WindowSelectionHistory()

        for tabID in tabIDs {
            history.recordRegularTabSelection(tabID, in: spaceID)
        }

        XCTAssertEqual(
            history.recentRegularTabIdsBySpace[spaceID],
            Array(tabIDs.reversed().prefix(20))
        )

        history.recordRegularTabSelection(tabIDs[10], in: spaceID)
        XCTAssertEqual(history.recentRegularTabIdsBySpace[spaceID]?.first, tabIDs[10])
        XCTAssertEqual(history.recentRegularTabIdsBySpace[spaceID]?.count, 20)
    }

    func testWindowSelectionHistoryRemovalPreservesExistingKeySemantics() {
        let spaceID = UUID()
        let tabID = UUID()
        let pinID = UUID()
        var history = WindowSelectionHistory()
        history.recentRegularTabIdsBySpace[spaceID] = [tabID]
        history.recentSelectionItemsBySpace[spaceID] = [
            .regularTab(tabID),
            .shortcutPin(pinID),
        ]

        history.removeFromRegularTabHistory(tabID)

        XCTAssertEqual(history.recentRegularTabIdsBySpace[spaceID], [])
        XCTAssertEqual(history.recentSelectionItemsBySpace[spaceID], [.shortcutPin(pinID)])

        history.removeFromShortcutLiveSelectionHistory(pinID)
        XCTAssertNil(history.recentSelectionItemsBySpace[spaceID])
    }

    func testWindowSelectionHistoryRemovesOneSpaceFootprintExactly() {
        let removedSpaceID = UUID()
        let retainedSpaceID = UUID()
        let removedTabID = UUID()
        let retainedTabID = UUID()
        let removedPinID = UUID()
        let retainedPinID = UUID()
        var history = WindowSelectionHistory()
        history.recentRegularTabIdsBySpace = [
            removedSpaceID: [retainedTabID],
            retainedSpaceID: [removedTabID, retainedTabID],
        ]
        history.recentSelectionItemsBySpace = [
            removedSpaceID: [.shortcutPin(retainedPinID)],
            retainedSpaceID: [
                .regularTab(removedTabID),
                .shortcutPin(removedPinID),
                .regularTab(retainedTabID),
                .shortcutPin(retainedPinID),
            ],
        ]

        XCTAssertTrue(history.removeReferences(
            toSpaceID: removedSpaceID,
            tabIDs: [removedTabID],
            shortcutPinIDs: [removedPinID]
        ))
        XCTAssertNil(history.recentRegularTabIdsBySpace[removedSpaceID])
        XCTAssertEqual(
            history.recentRegularTabIdsBySpace[retainedSpaceID],
            [retainedTabID]
        )
        XCTAssertNil(history.recentSelectionItemsBySpace[removedSpaceID])
        XCTAssertEqual(
            history.recentSelectionItemsBySpace[retainedSpaceID],
            [.regularTab(retainedTabID), .shortcutPin(retainedPinID)]
        )
        XCTAssertFalse(history.removeReferences(
            toSpaceID: removedSpaceID,
            tabIDs: [removedTabID],
            shortcutPinIDs: [removedPinID]
        ))
    }

    func testSidebarFolderProjectionStoreSetsAndRemovesPureValues() {
        let folderID = UUID()
        let childIDs = [UUID(), UUID()]
        var store = SidebarFolderProjectionStore()

        store.setProjection(
            SidebarFolderProjectionState(
                projectedChildIDs: childIDs,
                hasActiveProjection: true
            ),
            for: folderID
        )
        XCTAssertEqual(store.projection(for: folderID).projectedChildIDs, childIDs)
        XCTAssertTrue(store.projection(for: folderID).hasActiveProjection)

        store.setProjection(.empty, for: folderID)
        XCTAssertEqual(store.projection(for: folderID), .empty)
    }
}
