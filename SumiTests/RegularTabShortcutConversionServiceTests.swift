import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class RegularTabShortcutConversionServiceTests: XCTestCase {
    func testSplitConversionReplacesDurableTabWithPinAndProjectsEachWindow() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        var visibleIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { _ in visibleIds },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example/source",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example/companion",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        visibleIds = [source.id, companion.id]
        for windowState in [first, second] {
            windowState.currentSpaceId = space.id
            windowState.currentTabId = source.id
            windowState.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(source.id)
            )
        }

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                source,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: second.id
            )
        )

        let replacement = try XCTUnwrap(
            tabManager.splitGroupStore.group(id: group.id)
        )
        XCTAssertTrue(replacement.contains(.shortcutPin(pin.id)))
        XCTAssertFalse(replacement.contains(.regularTab(source.id)))
        XCTAssertEqual(
            first.splitSelection?.activeMemberID,
            .shortcutPin(pin.id)
        )
        XCTAssertEqual(
            second.splitSelection?.activeMemberID,
            .shortcutPin(pin.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: first.id),
            source
        )
        XCTAssertNotNil(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: second.id)
        )
    }

    func testPrimarySelectedWindowKeepsOriginalAndSecondaryMaterializesAfterCommit() throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let states = [primary.id: primary, secondary.id: secondary]
        var structuralEvents = 0
        var eventsSeenAtMaterialization: [Int] = []
        var materialized: [(UUID, UUID)] = []
        var cancellable: AnyCancellable?
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { tabId in
                primary.currentTabId == tabId ? primary.id : nil
            },
            materializeVisibleTabWebViewIfNeeded: { tab, window in
                eventsSeenAtMaterialization.append(structuralEvents)
                materialized.append((tab.id, window.id))
            }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://convert.example",
            in: space,
            activate: false
        )
        primary.currentSpaceId = space.id
        secondary.currentSpaceId = space.id
        primary.currentTabId = tab.id
        secondary.currentTabId = tab.id
        cancellable = tabManager.tabStructureEventBus.structureChangedPublisher
            .sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: secondary.id
            )
        )

        let secondaryTab = try XCTUnwrap(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: secondary.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: primary.id),
            tab
        )
        XCTAssertNotEqual(secondaryTab.id, tab.id)
        XCTAssertEqual(primary.currentTabId, tab.id)
        XCTAssertEqual(secondary.currentTabId, secondaryTab.id)
        XCTAssertEqual(materialized.map(\.0), [secondaryTab.id])
        XCTAssertEqual(materialized.map(\.1), [secondary.id])
        XCTAssertEqual(eventsSeenAtMaterialization, [1])
        XCTAssertEqual(structuralEvents, 1)
        _ = cancellable
    }

    func testSplitVisibleInAnotherWindowRejectsConversionWithoutPartialMutation() throws {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let states = [selected.id: selected, splitOnly.id: splitOnly]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnly.id ? [selected.currentTabId].compactMap(\.self) : []
            }
        )
        selected.tabManager = tabManager
        splitOnly.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let original = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/original",
            in: space,
            activate: false
        )
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/fallback",
            in: space,
            activate: false
        )
        selected.currentSpaceId = space.id
        selected.currentTabId = original.id
        splitOnly.currentSpaceId = space.id
        splitOnly.currentTabId = fallback.id
        splitOnly.activeTabForSpace[space.id] = original.id
        splitOnly.selectionHistory.recordRegularTabSelection(
            original.id,
            in: space.id
        )
        XCTAssertNil(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                original,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: selected.id
            )
        )

        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(original))
        XCTAssertFalse(original.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertEqual(splitOnly.currentTabId, fallback.id)
        XCTAssertEqual(splitOnly.activeTabForSpace[space.id], original.id)
        XCTAssertEqual(
            splitOnly.selectionHistory.recentRegularTabIdsBySpace[space.id]?
                .contains(original.id),
            true
        )
    }

    func testPrimaryLeaseChangeRejectsPreparedConversionWithoutMutation() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        var primaryWindowId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primaryWindowId },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://primary-lease.example",
            in: space,
            activate: false
        )
        for window in [first, second] {
            window.currentSpaceId = space.id
            window.currentTabId = tab.id
        }
        primaryWindowId = first.id
        let preparation = tabManager.regularTabShortcutConversion.prepare(
            tab,
            preferredWindowId: second.id
        )
        guard case .displayed = preparation else {
            return XCTFail("Expected displayed conversion preparation")
        }
        let firstSession = ShortcutConversionWindowSessionState(first)
        let secondSession = ShortcutConversionWindowSessionState(second)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        primaryWindowId = second.id
        let converted = tabManager.regularTabShortcutConversion.commit(
            tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: true
            )
        )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(first),
            firstSession
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(second),
            secondSession
        )
        _ = cancellable
    }

    func testPlanPreparedForAnotherTabRejectsBeforeStructuralMutation() throws {
        let window = BrowserWindowState()
        var visibleSplitIds: [UUID] = []
        var sourceTabId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            visibleSplitTabIds: { $0 == window.id ? visibleSplitIds : [] },
            primaryTrackedWindowId: { tabId in
                tabId == sourceTabId ? window.id : nil
            },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-source.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-companion.example",
            in: space,
            activate: false
        )
        let other = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-other.example",
            in: space,
            activate: false
        )
        sourceTabId = source.id
        window.tabManager = tabManager
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(source.id),
                    .regularTab(companion.id)
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        visibleSplitIds = group.memberIDs.compactMap { memberId in
            guard case .regularTab(let tabId) = memberId else { return nil }
            return tabId
        }
        XCTAssertTrue(tabManager.splitGroupMutations.insert(
            group,
            persist: false
        ))
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(
                source,
                preferredWindowId: window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid displayed conversion plan")
        }
        let windowSession = ShortcutConversionWindowSessionState(window)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let converted = tabManager.regularTabShortcutConversion
            .commit(
                other,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(other))
        XCTAssertFalse(source.isShortcutLiveInstance)
        XCTAssertFalse(other.isShortcutLiveInstance)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            group
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(window),
            windowSession
        )
        _ = cancellable
    }

    func testNoDisplayingWindowPreparesDetachedConversionWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden.example",
            in: space,
            activate: false
        )
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(tab)

        guard case .detached(let plan) = preparation else {
            return XCTFail("Expected a detached conversion plan")
        }
        XCTAssertEqual(plan.sourceTabId, tab.id)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
    }

    func testShortcutSidebarDropMovesStableMemberAndEveryWindowToTargetGroup() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/source",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/companion",
            in: space,
            activate: false
        )
        let firstPin = Self.pin(spaceID: space.id, index: 0)
        let secondPin = Self.pin(spaceID: space.id, index: 1)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [firstPin, secondPin],
            for: space.id
        )
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(
                    firstPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 0
                    )
                ),
                .shortcutPin(
                    secondPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 1
                    )
                ),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.replaceAll(
            expected: [],
            with: [sourceGroup, targetGroup],
            persist: false
        ))
        for state in [first, second] {
            state.currentSpaceId = space.id
            state.currentTabId = source.id
            state.splitSelection = WindowSplitSelection(
                groupID: sourceGroup.id,
                activeMemberID: .regularTab(source.id)
            )
        }

        let prepared = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .prepareShortcutSidebarDrop(
                    source,
                    into: targetGroup,
                    preferredWindowId: second.id
                )
        )
        let replacementTarget = try XCTUnwrap(targetGroup.inserting(
            prepared.member,
            relativeTo: .shortcutPin(firstPin.id),
            side: .right
        ))
        let replacement = prepared.expectedSplitGroups.compactMap { group in
            if group.id == sourceGroup.id {
                return group.removingMember(.regularTab(source.id))
            }
            return group.id == targetGroup.id ? replacementTarget : group
        }
        let pin = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .commitShortcutSidebarDrop(
                    prepared,
                    replacingSplitGroupsWith: replacement
                )
        )

        XCTAssertEqual(pin.id, prepared.candidatePin.id)
        XCTAssertNil(tabManager.splitGroupStore.group(id: sourceGroup.id))
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: targetGroup.id),
            replacementTarget
        )
        guard case .generatedSpacePinnedFromRegular(let restoredSpaceID, _) =
            replacementTarget.member(for: prepared.member.memberID)?
                .returnPlacement else {
            return XCTFail("Expected generated regular-tab return placement")
        }
        XCTAssertEqual(restoredSpaceID, space.id)
        for state in [first, second] {
            XCTAssertEqual(state.splitSelection?.groupID, targetGroup.id)
            XCTAssertEqual(
                state.splitSelection?.activeMemberID,
                prepared.member.memberID
            )
            XCTAssertNotNil(
                tabManager.liveShortcutTabs.tab(for: pin.id, in: state.id)
            )
        }
    }

    func testStaleShortcutSidebarDropDoesNotInsertCandidatePin() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/stale",
            in: space,
            activate: false
        )
        let firstPin = Self.pin(spaceID: space.id, index: 0)
        let secondPin = Self.pin(spaceID: space.id, index: 1)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [firstPin, secondPin],
            for: space.id
        )
        let target = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(
                    firstPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 0
                    )
                ),
                .shortcutPin(
                    secondPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 1
                    )
                ),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(target, persist: false))
        let prepared = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .prepareShortcutSidebarDrop(
                    source,
                    into: target,
                    preferredWindowId: UUID()
                )
        )
        let replacementTarget = try XCTUnwrap(target.inserting(
            prepared.member,
            relativeTo: .shortcutPin(firstPin.id),
            side: .right
        ))
        let replacement = prepared.expectedSplitGroups.map {
            $0.id == target.id ? replacementTarget : $0
        }
        let staleTarget = try XCTUnwrap(target.changingLayout(to: .horizontal))
        XCTAssertTrue(tabManager.splitGroupMutations.replace(
            target,
            with: staleTarget,
            persist: false
        ))

        XCTAssertNil(
            tabManager.regularTabShortcutConversion
                .commitShortcutSidebarDrop(
                    prepared,
                    replacingSplitGroupsWith: replacement
                )
        )
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(
                by: prepared.candidatePin.id
            )
        )
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertEqual(tabManager.splitGroupStore.group(id: target.id), staleTarget)
    }

    private static func pin(spaceID: UUID, index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceID,
            index: index,
            launchURL: URL(string: "https://sidebar-pin-\(index).example")!,
            title: "Pin \(index)"
        )
    }
}
