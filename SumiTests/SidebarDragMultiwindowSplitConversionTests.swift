import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragMultiwindowSplitConversionTests: XCTestCase {
    func testUnloadedPinnedSplitMoveToRegularMaterializesWholeGroup() throws {
        let window = BrowserWindowState()
        let profile = Profile(name: "Profile")
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] }
        )
        let browser = BrowserManager(runtimePorts: runtime)
        defer { browser.tabRuntimeLifecycle.shutdown() }
        browser.windowRegistry.register(window)
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        window.currentSpaceId = space.id
        let pins = try (0..<2).map { index in
            try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    profileId: profile.id,
                    spaceId: space.id,
                    index: index,
                    launchURL: URL(
                        string: "https://unloaded-\(index).example"
                    )!,
                    title: "Unloaded \(index)"
                ),
                at: index
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { SplitMember.shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profile.id,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(
            group,
            persist: false
        ))
        XCTAssertTrue(pins.allSatisfy {
            browser.liveShortcutTabs.entries(for: $0.id).isEmpty
        })
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spacePinned(space.id),
            item: .splitGroup(group.id, title: "Split")
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))

        let converted = try XCTUnwrap(browser.splitGroupStore.group(
            id: group.id
        ))
        XCTAssertEqual(
            converted.container,
            SplitGroupContainer.regularTabs(spaceId: space.id)
        )
        XCTAssertTrue(converted.memberIDs.allSatisfy {
            if case .regularTab = $0 { return true }
            return false
        })
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).count,
            2
        )
        XCTAssertTrue(browser.shortcutPinCollectionStateOwner
            .spacePinnedPins(for: space.id).isEmpty)
    }

    func testLoadedPinnedSplitMoveToRegularPromotesWholeGroupAtomically()
        throws {
        let window = BrowserWindowState()
        let profile = Profile(name: "Profile")
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] }
        )
        let browser = BrowserManager(runtimePorts: runtime)
        defer { browser.tabRuntimeLifecycle.shutdown() }
        browser.windowRegistry.register(window)
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        let pins = try (0..<2).map { index in
            try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    profileId: profile.id,
                    spaceId: space.id,
                    index: index,
                    launchURL: URL(
                        string: "https://loaded-\(index).example"
                    )!,
                    title: "Loaded \(index)"
                ),
                at: index
            ))
        }
        let tabs = pins.map { pin in
            let tab = Tab(
                url: pin.launchURL,
                name: pin.title,
                spaceId: space.id,
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = profile.id
            tab.bindToShortcutPin(pin)
            XCTAssertTrue(browser.liveShortcutTabs.register(
                tab,
                for: pin.id,
                in: window.id,
                presentationPage: LiveShortcutPresentationPageReceipt(
                    windowID: window.id,
                    spaceID: space.id,
                    profileID: profile.id
                )
            ))
            return tab
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { SplitMember.shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profile.id,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        window.currentTabId = tabs[0].id
        window.currentShortcutPinId = pins[0].id
        window.currentShortcutPinRole = .spacePinned
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(pins[0].id)
        )
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spacePinned(space.id),
            item: .splitGroup(group.id, title: "Split")
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))

        let converted = try XCTUnwrap(browser.splitGroupStore.group(
            id: group.id
        ))
        let regularIDs = converted.memberIDs.compactMap { memberID -> UUID? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return tabID
        }
        XCTAssertEqual(regularIDs, tabs.map(\.id))
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            tabs.map(\.id)
        )
        XCTAssertEqual(
            window.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(tabs[0].id)
            )
        )
        XCTAssertEqual(window.currentTabId, tabs[0].id)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertTrue(tabs.allSatisfy { !$0.isShortcutLiveInstance })
        XCTAssertTrue(pins.allSatisfy {
            browser.liveShortcutTabs.entries(for: $0.id).isEmpty
        })
    }

    func testRegularSplitRowReordersAsOneItemAcrossWindows() throws {
        try assertGroupReorder(secondarySelectsGroup: false)
    }

    func testSelectedRegularSplitRowReordersWithoutChangingWindowSelection()
        throws {
        try assertGroupReorder(secondarySelectsGroup: true)
    }

    func testRegularSplitRowMovesThroughPinnedAndEssentialsWithoutChangingGroupIdentity()
        throws {
        let window = BrowserWindowState()
        let profile = Profile(name: "Profile")
        var visibleSplitTabIDs: [UUID] = []
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id },
                executeProfileAssignment: { tab, _, intent in
                    tab.profileAssignment.commit(intent) ? .committed : .stale
                }
            ),
            visibleSplitTabIds: { _ in visibleSplitTabIDs }
        )
        let browser = BrowserManager(runtimePorts: runtime)
        defer { browser.tabRuntimeLifecycle.shutdown() }
        browser.windowRegistry.register(window)

        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let first = makeTab("first", in: space, browser: browser)
        let second = makeTab("second", in: space, browser: browser)
        visibleSplitTabIDs = [first.id, second.id]
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(first.id), .regularTab(second.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        window.currentTabId = first.id
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(first.id)
        )

        let item = SumiDragItem.splitGroup(group.id, title: "Split")
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spaceRegular(space.id),
            item: item
        ))
        let didMove = browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )
        XCTAssertTrue(didMove)
        XCTAssertEqual(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).count,
            2
        )

        let saved = try XCTUnwrap(browser.splitGroupStore.group(id: group.id))
        guard case .shortcutSidebar(let spaceID, _, nil, let index) = saved.container else {
            return XCTFail("Expected a top-level pinned split group")
        }
        XCTAssertEqual(spaceID, space.id)
        XCTAssertEqual(index, 0)
        XCTAssertTrue(saved.memberIDs.allSatisfy(\.isShortcutPin))
        let savedPinIDs = saved.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        }
        XCTAssertEqual(savedPinIDs.count, 2)
        XCTAssertIdentical(
            browser.shortcutPresentationOwner.shortcutLiveTab(
                for: savedPinIDs[0],
                in: window.id
            ),
            first
        )
        XCTAssertIdentical(
            browser.shortcutPresentationOwner.shortcutLiveTab(
                for: savedPinIDs[1],
                in: window.id
            ),
            second
        )
        XCTAssertEqual(
            window.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(savedPinIDs[0])
            )
        )
        XCTAssertEqual(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).count,
            2
        )
        XCTAssertFalse(browser.regularTabCollectionOwner.contains(first))
        XCTAssertFalse(browser.regularTabCollectionOwner.contains(second))

        let savedItem = SumiDragItem.splitGroup(saved.id, title: "Split")
        let savedScope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spacePinned(space.id),
            item: savedItem
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(saved),
                scope: savedScope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))
        let regularAgain = try XCTUnwrap(
            browser.splitGroupStore.group(id: group.id)
        )
        XCTAssertEqual(
            regularAgain.container,
            .regularTabs(spaceId: space.id)
        )
        XCTAssertTrue(regularAgain.memberIDs.allSatisfy { memberID in
            if case .regularTab = memberID { return true }
            return false
        })
        XCTAssertEqual(browser.regularTabCollectionOwner.tabs(in: space.id).count, 2)
        XCTAssertTrue(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        guard case .regularTab(let selectedRegularTabID) =
            window.splitSelection?.activeMemberID else {
            return XCTFail("Expected a selected regular split member")
        }

        let regularScope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spaceRegular(space.id),
            item: .splitGroup(regularAgain.id, title: "Split")
        ))
        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(regularAgain),
                scope: regularScope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .essentials,
                toIndex: 0
            )
        ))
        let essential = try XCTUnwrap(
            browser.splitGroupStore.group(id: group.id)
        )
        guard case .essentialSidebar(let profileID, let essentialIndex) =
            essential.container else {
            return XCTFail("Expected an Essential split group")
        }
        XCTAssertEqual(profileID, profile.id)
        XCTAssertEqual(essentialIndex, 0)
        let essentialPinIDs = essential.memberIDs.compactMap {
            memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        }
        XCTAssertEqual(essentialPinIDs.count, 2)
        XCTAssertIdentical(
            browser.shortcutPresentationOwner.shortcutLiveTab(
                for: essentialPinIDs[0],
                in: window.id
            ),
            first
        )
        XCTAssertIdentical(
            browser.shortcutPresentationOwner.shortcutLiveTab(
                for: essentialPinIDs[1],
                in: window.id
            ),
            second
        )
        let selectedEssentialPinID = try XCTUnwrap(
            essentialPinIDs.first { pinID in
                browser.shortcutPresentationOwner.shortcutLiveTab(
                    for: pinID,
                    in: window.id
                )?.id == selectedRegularTabID
            }
        )
        XCTAssertEqual(
            window.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(selectedEssentialPinID)
            )
        )
    }

    func testPinnedRegularRoundTripCanonicalizesStaleSplitDragPayload()
        throws {
        let window = BrowserWindowState()
        let profile = Profile(name: "Profile")
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id },
                executeProfileAssignment: { tab, _, intent in
                    tab.profileAssignment.commit(intent) ? .committed : .stale
                }
            )
        )
        let browser = BrowserManager(runtimePorts: runtime)
        defer { browser.tabRuntimeLifecycle.shutdown() }
        browser.windowRegistry.register(window)

        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let first = makeTab("first-stale", in: space, browser: browser)
        let second = makeTab("second-stale", in: space, browser: browser)
        let original = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(first.id), .regularTab(second.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(
            browser.splitGroupMutations.insert(original, persist: false)
        )
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        window.currentTabId = first.id
        window.splitSelection = WindowSplitSelection(
            groupID: original.id,
            activeMemberID: .regularTab(first.id)
        )

        let regularScope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spaceRegular(space.id),
            item: .splitGroup(original.id, title: "Split")
        ))
        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(original),
                scope: regularScope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        ))
        let saved = try XCTUnwrap(
            browser.splitGroupStore.group(id: original.id)
        )

        let pinnedScope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spacePinned(space.id),
            item: .splitGroup(saved.id, title: "Split")
        ))
        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                // Transition snapshots may still carry the pre-conversion
                // value. Identity, not its stale members, must be canonical.
                payload: .splitGroup(original),
                scope: pinnedScope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))

        let regularAgain = try XCTUnwrap(
            browser.splitGroupStore.group(id: original.id)
        )
        XCTAssertEqual(regularAgain.memberIDs.count, 2)
        XCTAssertEqual(Set(regularAgain.memberIDs), [
            .regularTab(first.id),
            .regularTab(second.id),
        ])
        XCTAssertEqual(
            Set(browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id)),
            [first.id, second.id]
        )
        XCTAssertTrue(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )

        let regularAgainScope = try XCTUnwrap(SidebarDragScope(
            windowState: window,
            sourceZone: .spaceRegular(space.id),
            item: .splitGroup(regularAgain.id, title: "Split")
        ))
        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                // Exercise the opposite stale representation too.
                payload: .splitGroup(saved),
                scope: regularAgainScope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        ))

        let savedAgain = try XCTUnwrap(
            browser.splitGroupStore.group(id: original.id)
        )
        XCTAssertEqual(savedAgain.memberIDs.count, 2)
        XCTAssertEqual(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).count,
            2
        )
        XCTAssertTrue(
            browser.regularTabCollectionOwner.tabs(in: space.id).isEmpty
        )
    }

    private func assertGroupReorder(
        secondarySelectsGroup: Bool
    ) throws {
        let primaryWindow = BrowserWindowState()
        let secondaryWindow = BrowserWindowState()
        let states = [
            primaryWindow.id: primaryWindow,
            secondaryWindow.id: secondaryWindow,
        ]
        let runtime = TestRuntimePorts.make(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } }
        )
        let browser = BrowserManager(runtimePorts: runtime)
        defer { browser.tabRuntimeLifecycle.shutdown() }

        let profileID = UUID()
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profileID
        ))
        let before = makeTab("before", in: space, browser: browser)
        let first = makeTab("first", in: space, browser: browser)
        let second = makeTab("second", in: space, browser: browser)
        let after = makeTab("after", in: space, browser: browser)
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(first.id), .regularTab(second.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        for window in states.values {
            window.currentSpaceId = space.id
            window.currentProfileId = profileID
        }
        primaryWindow.currentTabId = first.id
        primaryWindow.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(first.id)
        )
        secondaryWindow.currentTabId = secondarySelectsGroup ? second.id : before.id
        if secondarySelectsGroup {
            secondaryWindow.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(second.id)
            )
        }
        let primarySelection = primaryWindow.splitSelection
        let secondarySelection = secondaryWindow.splitSelection
        let item = SumiDragItem.splitGroup(group.id, title: "Split")
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: primaryWindow,
            sourceZone: .spaceRegular(space.id),
            item: item
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 4
            )
        ))

        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [before.id, after.id, first.id, second.id]
        )
        XCTAssertEqual(browser.splitGroupStore.group(id: group.id), group)
        XCTAssertEqual(primaryWindow.splitSelection, primarySelection)
        XCTAssertEqual(secondaryWindow.splitSelection, secondarySelection)
    }

    private func makeTab(
        _ name: String,
        in space: Space,
        browser: BrowserManager
    ) -> Tab {
        browser.regularTabLifecycleOwner.createNewTab(
            url: "https://\(name).example",
            in: space,
            activate: false
        )
    }
}
