import Combine
import XCTest

@testable import Sumi

@MainActor
final class TabLastSessionMergeTests: XCTestCase {
    func testPlannerPreservesLiveIdentityAndRestoresDeterministicOrderAndProfile() throws {
        let liveSpaceId = id("00000000-0000-0000-0000-000000000001")
        let updatedSpaceId = id("00000000-0000-0000-0000-000000000002")
        let restoredSpaceId = id("00000000-0000-0000-0000-000000000003")
        let liveProfileId = UUID()
        let restoredProfileId = UUID()
        let liveTabId = UUID()
        let restoredTabId = UUID()

        let live = TabLastSessionLiveState(
            spaces: [
                .init(id: liveSpaceId, profileId: liveProfileId),
                .init(id: updatedSpaceId, profileId: liveProfileId)
            ],
            currentSpaceId: liveSpaceId,
            foldersBySpace: [:],
            essentialPinsByProfile: [:],
            spacePinnedShortcuts: [:],
            regularTabsBySpace: [
                liveSpaceId: [.init(id: liveTabId, index: 7)]
            ]
        )
        let snapshot = TabPersistenceSnapshot(
            spaces: [
                space(id: updatedSpaceId, name: "Updated", index: 1, profileId: liveProfileId),
                space(id: restoredSpaceId, name: "Restored", index: 0, profileId: restoredProfileId)
            ],
            tabs: [
                regularTab(
                    id: restoredTabId,
                    spaceId: restoredSpaceId,
                    index: 4,
                    profileId: nil
                ),
                regularTab(
                    id: liveTabId,
                    spaceId: restoredSpaceId,
                    index: 0,
                    profileId: restoredProfileId
                )
            ],
            folders: [],
            state: .init(currentTabID: restoredTabId, currentSpaceID: restoredSpaceId)
        )

        let plan = TabLastSessionMergePlanner().makePlan(snapshot: snapshot, live: live)

        XCTAssertEqual(
            plan.orderedSpaceIds,
            [restoredSpaceId, updatedSpaceId, liveSpaceId]
        )
        XCTAssertEqual(plan.regularTabsBySpace[liveSpaceId]?.map(\.id), [liveTabId])
        XCTAssertEqual(plan.regularTabsBySpace[restoredSpaceId]?.map(\.id), [restoredTabId])
        guard case .restored(let restored)? = plan.regularTabsBySpace[restoredSpaceId]?.first else {
            return XCTFail("Expected a newly restored regular tab")
        }
        XCTAssertEqual(restored.profileId, restoredProfileId)
        XCTAssertEqual(plan.lazyRestoredTabIds, [restoredTabId])
        XCTAssertEqual(plan.requestedCurrentTabId, restoredTabId)
        guard case .select(let selectedSpaceId) = plan.spaceSelection else {
            return XCTFail("Expected restored space selection")
        }
        XCTAssertEqual(selectedSpaceId, restoredSpaceId)
    }

    func testPlannerUsesStableIdentityTieBreakAndDoesNotCrossPersistedItemKinds() {
        let spaceId = UUID()
        let profileId = UUID()
        let lowerId = id("00000000-0000-0000-0000-000000000010")
        let higherId = id("00000000-0000-0000-0000-000000000020")
        let folderAndTabId = UUID()
        let live = TabLastSessionLiveState(
            spaces: [.init(id: spaceId, profileId: profileId)],
            currentSpaceId: nil,
            foldersBySpace: [:],
            essentialPinsByProfile: [:],
            spacePinnedShortcuts: [:],
            regularTabsBySpace: [:]
        )
        let snapshot = TabPersistenceSnapshot(
            spaces: [space(id: spaceId, name: "Space", index: 0, profileId: profileId)],
            tabs: [
                regularTab(id: higherId, spaceId: spaceId, index: 2, profileId: profileId),
                regularTab(id: lowerId, spaceId: spaceId, index: 2, profileId: profileId),
                regularTab(id: folderAndTabId, spaceId: spaceId, index: 0, profileId: profileId)
            ],
            folders: [
                TabPersistenceFolder(
                    id: folderAndTabId,
                    name: "Folder",
                    icon: "folder",
                    color: "#112233",
                    spaceId: spaceId,
                    isOpen: true,
                    index: 0
                )
            ],
            state: .init(currentTabID: nil, currentSpaceID: nil)
        )

        let plan = TabLastSessionMergePlanner().makePlan(snapshot: snapshot, live: live)

        XCTAssertEqual(plan.foldersBySpace[spaceId]?.map(\.id), [folderAndTabId])
        XCTAssertEqual(plan.regularTabsBySpace[spaceId]?.map(\.id), [lowerId, higherId])
        XCTAssertFalse(plan.lazyRestoredTabIds.contains(folderAndTabId))
    }

    func testMaterializerCommitsOneStructuralTransactionWithCanonicalTabOrder() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let existingSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Existing",
            profileId: profileId
        )
        let existingTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/existing",
            in: existingSpace
        )
        let restoredSpaceId = UUID()
        let restoredProfileId = UUID()
        let firstRestoredTabId = UUID()
        let secondRestoredTabId = UUID()
        var structuralEventCount = 0
        let cancellable = tabManager.tabStructureEventBus.structureChangedPublisher.sink { _ in
            structuralEventCount += 1
        }
        let batchFlushesBefore = tabManager.structuralLookupCoordinator.batchFlushCount
        structuralEventCount = 0

        let snapshot = TabPersistenceSnapshot(
            spaces: [
                space(
                    id: existingSpace.id,
                    name: "Existing Updated",
                    index: 1,
                    profileId: profileId
                ),
                space(
                    id: restoredSpaceId,
                    name: "Restored",
                    index: 0,
                    profileId: restoredProfileId
                )
            ],
            tabs: [
                regularTab(
                    id: secondRestoredTabId,
                    spaceId: restoredSpaceId,
                    index: 9,
                    profileId: restoredProfileId
                ),
                regularTab(
                    id: firstRestoredTabId,
                    spaceId: restoredSpaceId,
                    index: 1,
                    profileId: nil
                )
            ],
            folders: [],
            state: .init(
                currentTabID: secondRestoredTabId,
                currentSpaceID: restoredSpaceId
            )
        )

        tabManager.lastSessionMergeMaterializer.merge(snapshot)

        XCTAssertEqual(structuralEventCount, 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [restoredSpaceId, existingSpace.id])
        XCTAssertTrue(tabManager.spaceStateOwner.spaces.last === existingSpace)
        XCTAssertEqual(existingSpace.name, "Existing Updated")
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabs(in: restoredSpaceId).map(\.id),
            [firstRestoredTabId, secondRestoredTabId]
        )
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabs(in: restoredSpaceId).map(\.index),
            [0, 1]
        )
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabs(in: restoredSpaceId).map(\.profileId),
            [restoredProfileId, restoredProfileId]
        )
        XCTAssertTrue(
            tabManager.regularTabCollectionStateOwner.tabs(in: existingSpace.id).first === existingTab
        )
        XCTAssertEqual(tabManager.spaceStateOwner.currentSpaceId, restoredSpaceId)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTabId, secondRestoredTabId)
        XCTAssertEqual(
            tabManager.tabCollectionMembershipOwner.tab(for: firstRestoredTabId)?.spaceId,
            restoredSpaceId
        )
        withExtendedLifetime(cancellable) {}
    }

    func testStartupResetRetiresEveryRegularTabAndClearsSelection() throws {
        var retiredTabIds = Set<UUID>()
        let tabManager = try makeInMemoryTabManager(
            requireRemoveAllWebViews: { tab, closeActiveFullscreenMedia in
                XCTAssertTrue(closeActiveFullscreenMedia)
                retiredTabIds.insert(tab.id)
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space", profileId: UUID())
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/one",
            in: space
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/two",
            in: space,
            activate: false
        )
        space.activeTabId = first.id
        tabManager.selectionStateOwner.replaceCurrentTab(first)

        tabManager.startupStateReset.resetRegularTabsAndShortcutLiveInstances()

        XCTAssertEqual(retiredTabIds, [first.id, second.id])
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabs(in: space.id).isEmpty)
        XCTAssertNil(tabManager.selectionStateOwner.currentTab)
        XCTAssertNil(space.activeTabId)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: first.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: second.id))
    }
}

private extension TabLastSessionMergeTests {
    func id(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func space(
        id: UUID,
        name: String,
        index: Int,
        profileId: UUID?
    ) -> TabPersistenceSpace {
        TabPersistenceSpace(
            id: id,
            name: name,
            icon: "circle",
            index: index,
            workspaceThemeData: nil,
            profileId: profileId
        )
    }

    func regularTab(
        id: UUID,
        spaceId: UUID,
        index: Int,
        profileId: UUID?
    ) -> TabPersistenceTab {
        TabPersistenceTab(
            id: id,
            urlString: "https://example.com/\(id.uuidString)",
            name: "Tab \(index)",
            index: index,
            spaceId: spaceId,
            isPinned: false,
            isSpacePinned: false,
            profileId: profileId,
            executionProfileId: nil,
            folderId: nil,
            iconAsset: nil,
            currentURLString: nil,
            canGoBack: false,
            canGoForward: false
        )
    }
}
