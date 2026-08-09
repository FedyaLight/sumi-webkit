import AppKit
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
extension SidebarDropCoordinatorBoundaryTests {
    func testSplitGroupRoundTripsThroughRealSidebarDropCoordinator()
        throws {
        let profile = Profile(name: "Split DnD Round Trip")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let tabs = (0..<3).map { index in
            browser.regularTabLifecycleOwner.createNewTab(
                url: "https://split-round-trip-\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: tabs.map { .regularTab($0.id) },
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: space.id),
                title: "Research Pair",
                iconAsset: "rectangle.split.2x1"
            )
        )
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowState.currentTabId = tabs[0].id
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(tabs[0].id)
        )
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )

        func pasteboard(
            source: TabDragManager.DragContainer
        ) -> NSPasteboard {
            makePasteboard(
                item: .splitGroup(group.id, title: "Split"),
                scope: SidebarDragScope(
                    windowId: nil,
                    spaceId: space.id,
                    profileId: profile.id,
                    sourceContainer: source,
                    sourceItemId: group.id,
                    sourceItemKind: .splitGroup
                )
            )
        }

        func assertGroupMetadata(
            _ current: SplitGroup,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(current.id, group.id, file: file, line: line)
            XCTAssertEqual(
                current.layoutKind,
                group.layoutKind,
                file: file,
                line: line
            )
            XCTAssertEqual(
                current.title,
                group.title,
                file: file,
                line: line
            )
            XCTAssertEqual(
                current.iconAsset,
                group.iconAsset,
                file: file,
                line: line
            )
        }

        func assertPinnedInvariant(
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let current = try XCTUnwrap(
                browser.splitGroupStore.group(id: group.id),
                file: file,
                line: line
            )
            assertGroupMetadata(current, file: file, line: line)
            let pinIDs: [UUID] = current.memberIDs.compactMap {
                memberID -> UUID? in
                guard case .shortcutPin(let pinID) = memberID else {
                    return nil
                }
                return pinID
            }
            XCTAssertEqual(pinIDs.count, tabs.count, file: file, line: line)
            let pins: [ShortcutPin] = try pinIDs.map {
                try XCTUnwrap(
                    browser.shortcutPinCollectionStateOwner.shortcutPin(by: $0),
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(
                pins.map(\.launchURL),
                tabs.map(\.url),
                file: file,
                line: line
            )
            XCTAssertEqual(
                Set(browser.shortcutPinCollectionStateOwner
                    .spacePinnedPins(for: space.id).map(\.id)),
                Set(pinIDs),
                file: file,
                line: line
            )
            for (pinID, tab) in zip(pinIDs, tabs) {
                XCTAssertIdentical(
                    browser.shortcutPresentationOwner.shortcutLiveTab(
                        for: pinID,
                        in: windowState.id
                    ),
                    tab,
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(
                windowState.splitSelection,
                WindowSplitSelection(
                    groupID: group.id,
                    activeMemberID: .shortcutPin(pinIDs[0])
                ),
                file: file,
                line: line
            )
        }

        func assertRegularInvariant(
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let current = try XCTUnwrap(
                browser.splitGroupStore.group(id: group.id),
                file: file,
                line: line
            )
            assertGroupMetadata(current, file: file, line: line)
            XCTAssertEqual(
                current.memberIDs,
                tabs.map { .regularTab($0.id) },
                file: file,
                line: line
            )
            let regularTabs =
                browser.regularTabCollectionOwner.tabs(in: space.id)
            XCTAssertEqual(
                regularTabs.map(\.url),
                tabs.map(\.url),
                file: file,
                line: line
            )
            for (currentTab, originalTab) in zip(regularTabs, tabs) {
                XCTAssertIdentical(
                    currentTab,
                    originalTab,
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(
                SidebarVisualSceneProjection.regularRun(
                    tabIDs: regularTabs.map(\.id),
                    groups: browser.splitGroupSidebarOrdering
                        .regularGroups(for: space.id)
                ).rows.map(\.identity),
                [.splitGroup(group.id)],
                file: file,
                line: line
            )
            XCTAssertEqual(
                windowState.splitSelection,
                WindowSplitSelection(
                    groupID: group.id,
                    activeMemberID: .regularTab(tabs[0].id)
                ),
                file: file,
                line: line
            )
        }

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard(source: .spaceRegular(space.id)),
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        try assertPinnedInvariant()
        XCTAssertTrue(
            browser.regularTabCollectionOwner.tabs(in: space.id).isEmpty
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard(source: .spacePinned(space.id)),
            resolution: SidebarDropResolution(
                slot: .spaceRegular(spaceId: space.id, slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        try assertRegularInvariant()
        XCTAssertTrue(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard(source: .spaceRegular(space.id)),
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 0),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        try assertPinnedInvariant()
        XCTAssertTrue(
            browser.regularTabCollectionOwner.tabs(in: space.id).isEmpty
        )

        let savedGroup = try XCTUnwrap(
            browser.splitGroupStore.group(id: group.id)
        )
        context.browserContext.splitGroupLifecycle.unload(
            savedGroup,
            in: windowState
        )
        XCTAssertEqual(
            browser.splitGroupStore.group(id: group.id),
            savedGroup
        )
        XCTAssertTrue(
            browser.regularTabCollectionOwner.tabs(in: space.id).isEmpty
        )
        XCTAssertNil(windowState.splitSelection)
        for memberID in savedGroup.memberIDs {
            guard case .shortcutPin(let pinID) = memberID else {
                return XCTFail("Expected only shortcut members after save")
            }
            XCTAssertTrue(
                browser.liveShortcutTabs.entries(for: pinID).isEmpty
            )
        }
    }

    func testPinnedShortcutDropsAboveSplitAtThePresentedBoundary() throws {
        let profile = Profile(name: "Pinned Split Boundary")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let pins = (0..<4).map { index in
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                profileId: profile.id,
                spaceId: space.id,
                index: index,
                launchURL: URL(string: "https://pinned-boundary-\(index).example")!,
                title: "Pinned \(index)"
            )
        }
        for pin in pins {
            XCTAssertNotNil(browser.shortcutPinStoreOwner.insert(
                pin,
                at: pin.index,
                openTargetFolder: false
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[1].id), .shortcutPin(pins[2].id)],
            layoutKind: .horizontal,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profile.id,
                folderId: nil,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.shortcut(pins[0].id), .splitGroup(group.id), .shortcut(pins[3].id)]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let splitPasteboard = makePasteboard(
            item: SumiDragItem.splitGroup(group.id, title: "Split"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spacePinned(space.id),
                sourceItemId: group.id,
                sourceItemKind: .splitGroup
            )
        )
        XCTAssertFalse(context.dragTransactions.commit(
            pasteboard: splitPasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.shortcut(pins[0].id), .splitGroup(group.id), .shortcut(pins[3].id)]
        )

        let pasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(pins[3].id, title: "Trailing"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spacePinned(space.id),
                sourceItemId: pins[3].id,
                sourceItemKind: .tab
            )
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 1),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.shortcut(pins[0].id), .shortcut(pins[3].id), .splitGroup(group.id)]
        )

        let sameSidePasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(pins[0].id, title: "Leading"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spacePinned(space.id),
                sourceItemId: pins[0].id,
                sourceItemKind: .tab
            )
        )
        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: sameSidePasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.shortcut(pins[3].id), .shortcut(pins[0].id), .splitGroup(group.id)]
        )
    }

    func testRegularTabDropsIntoPinnedAbovePresentedSplitBoundary() throws {
        let profile = Profile(name: "Pinned Cross-Container Boundary")
        let browser = makeSafariExtensionTestBrowserManager(profile: profile)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Work",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let pins = (0..<4).map { index in
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                profileId: profile.id,
                spaceId: space.id,
                index: index,
                launchURL: URL(string: "https://cross-pinned-\(index).example")!,
                title: "Pinned \(index)"
            )
        }
        for pin in pins {
            XCTAssertNotNil(browser.shortcutPinStoreOwner.insert(
                pin,
                at: pin.index,
                openTargetFolder: false
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[1].id), .shortcutPin(pins[2].id)],
            layoutKind: .horizontal,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profile.id,
                folderId: nil,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://cross-regular.example",
            in: space,
            activate: false
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        browser.windowRegistry.register(windowState)
        let context = WindowSidebarContext.make(
            browserManager: browser,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            nowPlayingController: SumiNativeNowPlayingController()
        )
        let pasteboard = makePasteboard(
            item: SumiDragItem(tabId: tab.id, title: "Regular"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .spaceRegular(space.id),
                sourceItemId: tab.id,
                sourceItemKind: .tab
            )
        )

        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: pasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 1),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        let convertedPin = try XCTUnwrap(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id)
                .first {
                    $0.id != pins[0].id
                    && $0.id != pins[1].id
                    && $0.id != pins[2].id
                    && $0.id != pins[3].id
                }
        )
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .shortcut(pins[0].id),
                .shortcut(convertedPin.id),
                .splitGroup(group.id),
                .shortcut(pins[3].id),
            ]
        )

        let favorite = try makeFavoritePin(
            browser,
            in: space,
            profileId: profile.id,
            url: "https://cross-favorite.example",
            index: 0
        )
        let favoritePasteboard = makePasteboard(
            item: SumiDragItem.shortcutPin(favorite.id, title: "Favorite"),
            scope: SidebarDragScope(
                windowId: nil,
                spaceId: space.id,
                profileId: profile.id,
                sourceContainer: .favorite,
                sourceItemId: favorite.id,
                sourceItemKind: .tab
            )
        )
        XCTAssertTrue(context.dragTransactions.commit(
            pasteboard: favoritePasteboard,
            resolution: SidebarDropResolution(
                slot: .spacePinned(spaceId: space.id, slot: 2),
                folderIntent: .none,
                activeHoveredFolderId: nil
            ),
            windowState: windowState
        ))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .shortcut(pins[0].id),
                .shortcut(convertedPin.id),
                .shortcut(favorite.id),
                .splitGroup(group.id),
                .shortcut(pins[3].id),
            ]
        )
    }

    func testOperationIndexProjectionPreservesSameAndCrossContainerSemantics() {
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 2,
                sourceContainer: .favorite,
                targetContainer: .favorite,
                sourceIndex: 0,
                sourceItemCount: 4
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 2,
                sourceContainer: .favorite,
                targetContainer: .spacePinned(UUID()),
                sourceIndex: 0,
                sourceItemCount: 4
            ),
            2
        )
        XCTAssertEqual(
            SidebarDropProjection.operationIndex(
                visualIndex: 99,
                sourceContainer: .favorite,
                targetContainer: .favorite,
                sourceIndex: 1,
                sourceItemCount: 3
            ),
            3
        )
    }

}
