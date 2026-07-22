import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarVisualSceneProjectionTests: XCTestCase {
    func testSelectedRegularTabProjectsToItsOwnVisualRow() {
        let tab = makeTab()
        let browser = BrowserManager()
        let window = BrowserWindowState()
        let projection = SidebarVisualSceneProjection(
            inventory: .ephemeral(spaceID: UUID(), regularTabs: [tab]),
            selection: makeSelection(browser: browser),
            selectionSnapshot: SidebarWindowSelectionSnapshot(
                shortcut: ShortcutSelectionSnapshot(currentTabID: tab.id)
            ),
            windowState: window
        )

        XCTAssertEqual(
            projection.selectedItemRevealPath,
            SidebarSelectedItemRevealPath([.regularTab(tab.id)])
        )
    }

    func testSelectedRegularSplitMemberProjectsToWholeGroupRow() throws {
        let members = [makeTab(), makeTab()]
        let group = try XCTUnwrap(SplitGroup.make(
            members: members.map { .regularTab($0.id) },
            layoutKind: .horizontal,
            container: .regularTabs(spaceId: nil)
        ))
        let browser = BrowserManager()
        let projection = SidebarVisualSceneProjection(
            inventory: makeInventory(
                spaceID: UUID(),
                regularTabs: members,
                splitGroups: [group]
            ),
            selection: makeSelection(browser: browser),
            selectionSnapshot: SidebarWindowSelectionSnapshot(
                shortcut: ShortcutSelectionSnapshot(currentTabID: members[1].id)
            ),
            windowState: BrowserWindowState()
        )

        XCTAssertEqual(
            projection.selectedItemRevealPath,
            SidebarSelectedItemRevealPath([.splitGroup(group.id)])
        )
    }

    func testSelectedShortcutSplitMemberProjectsToWholeGroupRow() throws {
        let fixture = try PublicationFixture(pinCount: 2)
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        let projection = SidebarVisualSceneProjection(
            inventory: makeInventory(browser: fixture.browser, spaceID: spaceID),
            selection: makeSelection(browser: fixture.browser),
            selectionSnapshot: SidebarWindowSelectionSnapshot(
                shortcut: ShortcutSelectionSnapshot(
                    currentShortcutPinID: fixture.pins[1].id
                )
            ),
            windowState: fixture.window
        )

        XCTAssertEqual(
            projection.selectedItemRevealPath,
            SidebarSelectedItemRevealPath([.splitGroup(fixture.group.id)])
        )
    }

    func testRegularRunAlwaysProjectsWholeSplitAsOneRow() throws {
        for memberCount in 2...4 {
            let leading = makeTab()
            let members = (0..<memberCount).map { _ in makeTab() }
            let trailing = makeTab()
            let group = try XCTUnwrap(SplitGroup.make(
                members: members.map { .regularTab($0.id) },
                layoutKind: .vertical,
                container: .regularTabs(spaceId: nil)
            ))

            let run = SidebarVisualSceneProjection.regularRun(
                tabIDs: ([leading] + members + [trailing]).map(\.id),
                groups: [group]
            )

            XCTAssertEqual(
                run.rows.map(\.identity),
                [.tab(leading.id), .splitGroup(group.id), .tab(trailing.id)]
            )
            XCTAssertEqual(
                (0...run.rows.count).map(run.rawInsertionIndex),
                [0, 1, memberCount + 1, memberCount + 2]
            )
            let hitMetrics = SidebarRegularListHitMetrics(
                frame: CGRect(x: 0, y: 0, width: 300, height: 112),
                rowIdentities: run.rows.map(\.identity)
            )
            XCTAssertEqual(hitMetrics.rowCount, 3)
            XCTAssertEqual(
                hitMetrics.presentedBoundary(at: 2),
                run.boundary(at: 2)
            )
        }
    }

    func testRegularPresentedBoundaryRejectsChangedNeighbors() throws {
        let first = makeTab()
        let splitA = makeTab()
        let splitB = makeTab()
        let last = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(splitA.id), .regularTab(splitB.id)],
            layoutKind: .horizontal,
            container: .regularTabs(spaceId: nil)
        ))
        let original = SidebarVisualSceneProjection.regularRun(
            tabIDs: [first.id, splitA.id, splitB.id, last.id],
            groups: [group]
        )
        let presented = original.boundary(at: 2)
        let changed = SidebarVisualSceneProjection.regularRun(
            tabIDs: [first.id, last.id, splitA.id, splitB.id],
            groups: [group]
        )

        XCTAssertNil(changed.visualIndex(for: presented))
    }

    func testUnloadingCollapsedFolderSplitRemovesItsVisibleProjection()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            foldered: true,
            hostedSplit: true
        )
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        let inventory = makeInventory(
            browser: fixture.browser,
            spaceID: spaceID
        )
        let selection = makeSelection(browser: fixture.browser)

        let before = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: SidebarWindowSelectionSnapshot(
                windowState: fixture.window
            ),
            windowState: fixture.window
        ).launcherItems(inventory.descendantItems(for: try XCTUnwrap(fixture.folder).id))
        XCTAssertEqual(before.map(\.id), [fixture.group.id])
        XCTAssertEqual(before.map(\.isLive), [true])

        XCTAssertNotNil(
            fixture.browser.composeSplitShortcutHostedUnload()
                .unloadShortcutHostedSplitGroup(
                    fixture.group,
                    in: fixture.window
                )
        )

        let after = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: selection,
            selectionSnapshot: SidebarWindowSelectionSnapshot(
                windowState: fixture.window
            ),
            windowState: fixture.window
        ).launcherItems(inventory.descendantItems(for: try XCTUnwrap(fixture.folder).id))

        XCTAssertEqual(after.map(\.id), [fixture.group.id])
        XCTAssertEqual(after.map(\.isLive), [false])
        let stickyContext = SidebarFolderStickyProjectionPolicy.Context(
            isFolderOpen: false,
            orderedDescendantItemIDs: after.map(\.id),
            visibleEligibleItemIDs: Set(after.filter(\.isLive).map(\.id)),
            selectedDescendantItemID: nil
        )
        XCTAssertTrue(
            SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
                sticky: [fixture.group.id],
                context: stickyContext
            ).isEmpty
        )
        XCTAssertEqual(
            fixture.browser.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
    }

    func testPartiallyLoadedSplitIsNotStickyEligible() throws {
        let browser = BrowserManager()
        let window = BrowserWindowState()
        browser.windowRegistry.register(window)
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
        window.currentSpaceId = space.id
        let folder = try XCTUnwrap(
            browser.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Folder"
            )
        )
        let pins = try (0..<2).map { index in
            try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(
                    index: index,
                    spaceID: space.id,
                    folderID: folder.id
                ),
                at: index
            ))
        }
        _ = try XCTUnwrap(browser.shortcutTabMaterializer.materialize(
            pins[0],
            in: window.id,
            currentSpaceId: space.id
        ))
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: folder.id,
                index: 0
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        let inventory = makeInventory(browser: browser, spaceID: space.id)
        let items = SidebarVisualSceneProjection(
            inventory: inventory,
            selection: makeSelection(browser: browser),
            selectionSnapshot: SidebarWindowSelectionSnapshot(windowState: window),
            windowState: window
        ).launcherItems(inventory.descendantItems(for: folder.id))

        XCTAssertEqual(items.map(\.id), [group.id])
        XCTAssertEqual(items.map(\.isLive), [false])
    }

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            name: "Tab",
            favicon: "globe"
        )
    }

    private func makeInventory(
        browser: BrowserManager,
        spaceID: UUID
    ) -> SidebarSpaceInventorySnapshot {
        SidebarPinnedInventoryProjection(
            folders: browser.folderCollectionStateOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            splitGroups: browser.splitGroupStore,
            splitOrdering: browser.splitGroupSidebarOrdering
        ).snapshot(for: spaceID, regularTabs: [])
    }

    private func makeInventory(
        spaceID: UUID,
        regularTabs: [Tab],
        splitGroups: [SplitGroup]
    ) -> SidebarSpaceInventorySnapshot {
        SidebarSpaceInventorySnapshot(
            spaceID: spaceID,
            regularTabs: regularTabs,
            topLevelItems: [],
            topLevelFolders: [],
            topLevelPins: [],
            childFoldersByParentID: [:],
            folderPinsByFolderID: [:],
            folderItemsByFolderID: [:],
            foldersByID: [:],
            pinsByID: [:],
            tabsByID: Dictionary(
                uniqueKeysWithValues: regularTabs.map { ($0.id, $0) }
            ),
            splitGroupsByID: Dictionary(
                uniqueKeysWithValues: splitGroups.map { ($0.id, $0) }
            )
        )
    }

    private func makeSelection(
        browser: BrowserManager
    ) -> SidebarWindowSelectionQuery {
        SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: SidebarWindowIdentityQuery(registry: browser.windowRegistry),
            windowTabs: browser.windowTabContext,
            shortcutPresentation: browser.shortcutPresentationOwner,
            splitQuery: browser.splitQuery
        )
    }
}
