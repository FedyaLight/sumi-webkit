import Combine
import SumiWebRuntime
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
                .init(id: updatedSpaceId, profileId: liveProfileId),
            ],
            currentSpaceId: liveSpaceId,
            foldersBySpace: [:],
            essentialPinsByProfile: [:],
            spacePinnedShortcuts: [:],
            regularTabsBySpace: [
                liveSpaceId: [.init(id: liveTabId, index: 7)],
            ]
        )
        let snapshot = TabPersistenceSnapshot(
            spaces: [
                space(id: updatedSpaceId, name: "Updated", index: 1, profileId: liveProfileId),
                space(id: restoredSpaceId, name: "Restored", index: 0, profileId: restoredProfileId),
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
                ),
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
                regularTab(id: folderAndTabId, spaceId: spaceId, index: 0, profileId: profileId),
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
                ),
            ],
            state: .init(currentTabID: nil, currentSpaceID: nil)
        )

        let plan = TabLastSessionMergePlanner().makePlan(snapshot: snapshot, live: live)

        XCTAssertEqual(plan.foldersBySpace[spaceId]?.map(\.id), [folderAndTabId])
        XCTAssertEqual(plan.regularTabsBySpace[spaceId]?.map(\.id), [lowerId, higherId])
        XCTAssertFalse(plan.lazyRestoredTabIds.contains(folderAndTabId))
    }

    func testMaterializerCommitsOneStructuralTransactionWithCanonicalTabOrder() throws {
        let fixture = try LastSessionFixture()
        let tabManager = fixture.manager
        let profileId = UUID()
        let existingSpace = Space(
            name: "Existing",
            profileId: profileId
        )
        let existingTab = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/existing")!,
            spaceId: existingSpace.id
        )
        tabManager.stateStore.spaces.replaceSpaces([existingSpace])
        tabManager.stateStore.regularTabs.replaceTabsBySpace([
            existingSpace.id: [existingTab],
        ])
        fixture.membership.attach(existingTab)
        let restoredSpaceId = UUID()
        let restoredProfileId = UUID()
        let firstRestoredTabId = UUID()
        let secondRestoredTabId = UUID()
        var structuralEventCount = 0
        let cancellable = tabManager.tabStructureEventBus.structureChangedPublisher.sink { _ in
            structuralEventCount += 1
        }
        let batchFlushesBefore = fixture.structuralLookup.batchFlushCount
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
                ),
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
                ),
            ],
            folders: [],
            state: .init(
                currentTabID: secondRestoredTabId,
                currentSpaceID: restoredSpaceId
            )
        )

        fixture.merge.merge(snapshot)

        XCTAssertEqual(structuralEventCount, 1)
        XCTAssertEqual(fixture.structuralLookup.batchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.stateStore.spaces.spaces.map(\.id), [restoredSpaceId, existingSpace.id])
        XCTAssertTrue(tabManager.stateStore.spaces.spaces.last === existingSpace)
        XCTAssertEqual(existingSpace.name, "Existing Updated")
        XCTAssertEqual(
            tabManager.stateStore.regularTabs.tabs(in: restoredSpaceId).map(\.id),
            [firstRestoredTabId, secondRestoredTabId]
        )
        XCTAssertEqual(
            tabManager.stateStore.regularTabs.tabs(in: restoredSpaceId).map(\.index),
            [0, 1]
        )
        XCTAssertEqual(
            tabManager.stateStore.regularTabs.tabs(in: restoredSpaceId).map(\.profileId),
            [restoredProfileId, restoredProfileId]
        )
        XCTAssertTrue(
            tabManager.stateStore.regularTabs.tabs(in: existingSpace.id).first === existingTab
        )
        XCTAssertEqual(tabManager.stateStore.spaces.currentSpaceId, restoredSpaceId)
        XCTAssertEqual(tabManager.stateStore.selection.currentTabId, secondRestoredTabId)
        XCTAssertEqual(
            fixture.membership.tab(for: firstRestoredTabId)?.spaceId,
            restoredSpaceId
        )
        withExtendedLifetime(cancellable) {}
    }

    func testMaterializerRejectsUnavailableAdmissionBeforeFirstMutation() throws {
        let fixture = try LastSessionFixture(
            profileReferenceAdmission: .failClosed()
        )
        let tabManager = fixture.manager
        let profileID = UUID()
        let spaceID = UUID()
        let revisionBefore = fixture.structuralLookup.mutationRevision
        let snapshot = TabPersistenceSnapshot(
            spaces: [space(
                id: spaceID,
                name: "Blocked",
                index: 0,
                profileId: profileID
            )],
            tabs: [regularTab(
                id: UUID(),
                spaceId: spaceID,
                index: 0,
                profileId: profileID
            )],
            folders: [],
            state: .init(currentTabID: nil, currentSpaceID: spaceID)
        )

        XCTAssertFalse(fixture.merge.merge(snapshot))
        XCTAssertTrue(tabManager.stateStore.spaces.spaces.isEmpty)
        XCTAssertTrue(
            tabManager.stateStore.regularTabs
                .tabsBySpaceSnapshot()
                .isEmpty
        )
        XCTAssertEqual(
            fixture.structuralLookup.mutationRevision,
            revisionBefore
        )
    }

    func testStartupResetRetiresEveryRegularTabAndClearsSelection() throws {
        var retiredTabIds = Set<UUID>()
        let fixture = try LastSessionFixture()
        let tabManager = fixture.manager
        let space = Space(name: "Space", profileId: UUID())
        let first = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/one")!,
            spaceId: space.id
        )
        let second = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/two")!,
            spaceId: space.id
        )
        tabManager.stateStore.spaces.replaceSpaces([space])
        tabManager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [first, second],
        ])
        fixture.membership.attach(first)
        fixture.membership.attach(second)
        for tab in [first, second] {
            var cleanupRuntime = TabWebViewCleanupRuntime.inactive
            cleanupRuntime.removeAllWebViews = {
                tab,
                closeActiveFullscreenMedia,
                intent in
                XCTAssertTrue(closeActiveFullscreenMedia)
                XCTAssertEqual(intent, .retirement)
                retiredTabIds.insert(tab.id)
                return WebViewTabTeardownResult(
                    discoveredWebViewCount: 1,
                    cleanedWebViewCount: 1,
                    deferredWebViewCount: 0,
                    unscheduledProtectedWebViewCount: 0
                )
            }
            tab.navigationRuntime.webViewCleanupRuntime = cleanupRuntime
        }
        space.activeTabId = first.id
        tabManager.stateStore.selection.replaceCurrentTab(first)

        fixture.startupReset.resetRegularTabsAndShortcutLiveInstances()

        XCTAssertEqual(retiredTabIds, [first.id, second.id])
        XCTAssertTrue(tabManager.stateStore.regularTabs.tabs(in: space.id).isEmpty)
        XCTAssertNil(tabManager.stateStore.selection.currentTab)
        XCTAssertNil(space.activeTabId)
        XCTAssertNil(fixture.membership.tab(for: first.id))
        XCTAssertNil(fixture.membership.tab(for: second.id))
    }

    func testStartupResetDoesNotCommitWhenPhysicalCleanupIsBlocked() throws {
        let fixture = try LastSessionFixture()
        let tabManager = fixture.manager
        let space = Space(name: "Space")
        let tab = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/blocked")!,
            spaceId: space.id
        )
        tabManager.stateStore.spaces.replaceSpaces([space])
        tabManager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        fixture.membership.attach(tab)
        space.activeTabId = tab.id
        tabManager.stateStore.selection.replaceCurrentTab(tab)
        var cleanupRuntime = TabWebViewCleanupRuntime.inactive
        cleanupRuntime.removeAllWebViews = { _, _, _ in
            WebViewTabTeardownResult(
                discoveredWebViewCount: 1,
                cleanedWebViewCount: 0,
                deferredWebViewCount: 0,
                unscheduledProtectedWebViewCount: 0,
                blockedWebViewCount: 1
            )
        }
        tab.navigationRuntime.webViewCleanupRuntime = cleanupRuntime

        fixture.startupReset.resetRegularTabsAndShortcutLiveInstances()

        XCTAssertEqual(
            tabManager.stateStore.regularTabs.tabs(in: space.id).map(\.id),
            [tab.id]
        )
        XCTAssertIdentical(tabManager.stateStore.selection.currentTab, tab)
        XCTAssertEqual(space.activeTabId, tab.id)
        XCTAssertIdentical(
            fixture.membership.tab(for: tab.id),
            tab
        )
    }
}

@MainActor
private final class LastSessionFixture {
    let manager: TabManager
    let merge: TabLastSessionMergeMaterializer
    let startupReset: TabStartupStateReset
    let membership: TabCollectionMembershipOwner
    let structuralLookup: TabStructuralLookupCoordinator

    init(
        profileReferenceAdmission: ProfileReferenceAdmissionLedger? = nil
    ) throws {
        let container = try makeInMemoryStartupModelContainer()
        let eventBus = TabStructureEventBus()
        let manager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: try profileReferenceAdmission
                ?? ProfileReferenceAdmissionLedger(context: container.mainContext),
            loadPersistedState: false,
            tabStructureEventBus: eventBus
        )
        let state = manager.stateStore
        let connection = manager.runtimePortConnection
        let runtimePreparation = TabRuntimePreparationOwner(
            runtimeConnection: connection
        )
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: eventBus,
            stateStore: state
        )
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookup.lookupOwner,
            state: state,
            runtimePreparation: runtimePreparation,
            runtimeConnection: connection
        )
        let mutationPublisher = TabStructuralMutationPublisher(
            persistence: manager.structuralPersistence,
            faviconService: manager.faviconService,
            lookup: structuralLookup,
            changes: manager.objectWillChange,
            regularTabs: state.regularTabs
        )
        let structuralMutations = TabStructuralCollectionMutationOwner(
            store: TabStructuralCollectionStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            snapshots: TabStructuralCollectionSnapshotStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            publisher: mutationPublisher
        )
        let lazyRestore = TabLazyRestoreCoordinator(
            spaces: state.spaces,
            regularTabs: state.regularTabs,
            membership: membership
        )
        let spacePinnedOrder = SpacePinnedOrderTransaction(
            folders: state.folders,
            pins: state.shortcutPins,
            mutations: structuralMutations
        )
        let spacePinnedStructure = SpacePinnedStructureOwner(
            folders: state.folders,
            pins: state.shortcutPins,
            splitGroups: state.splitGroups,
            orderTransaction: spacePinnedOrder
        )
        let runtimeTeardown = TabRuntimeTeardownService(
            persistence: manager.structuralPersistence,
            membership: membership,
            webViewSessions: manager.tabFactory.webViewSessions
        )
        let liveShortcutTabs = LiveShortcutTabRegistry(
            storage: state.transientTabs,
            structuralLookup: structuralLookup
        )
        let liveShortcutRetirement = LiveShortcutTabBatchRetirement(
            storage: state.transientTabs,
            structuralLookup: structuralLookup
        )
        let splitMutations = SplitGroupMutationService(
            store: state.splitGroups,
            publication: mutationPublisher
        )

        let merge = TabLastSessionMergeMaterializer(
            planning: TabLastSessionMergePlanningService(
                planner: TabLastSessionMergePlanner(),
                snapshotter: TabLastSessionLiveStateSnapshotter(
                    spaces: state.spaces,
                    folders: state.folders,
                    shortcutPins: state.shortcutPins,
                    regularTabs: state.regularTabs
                )
            ),
            profileAdmission: TabLastSessionProfileAdmissionTransaction(
                ledger: manager.profileReferenceAdmission
            ),
            structuralLookup: structuralLookup,
            commitTransaction: TabLastSessionMergeCommitTransaction(
                spaces: TabLastSessionSpaceMaterializer(
                    spaces: state.spaces,
                    persistence: manager.structuralPersistence,
                    changes: manager.objectWillChange
                ),
                folders: TabLastSessionFolderMaterializer(
                    structuralMutations: structuralMutations
                ),
                shortcuts: TabLastSessionShortcutMaterializer(
                    structuralMutations: structuralMutations,
                    spacePinnedStructure: spacePinnedStructure
                ),
                regularTabs: TabLastSessionRegularTabMaterializer(
                    structuralMutations: structuralMutations,
                    membership: membership,
                    tabFactory: manager.tabFactory
                ),
                selection: TabLastSessionSelectionMaterializer(
                    spaces: state.spaces,
                    selection: state.selection
                )
            ),
            settlement: TabLastSessionMergeSettlement(
                lazyRestore: lazyRestore,
                persistence: manager.structuralPersistence
            )
        )

        let startupReset = TabStartupStateReset(
            structuralLookup: structuralLookup,
            runtimeReset: TabStartupRuntimeResetTransaction(
                state: state,
                liveShortcutTabs: liveShortcutTabs,
                runtimeConnection: connection,
                runtimeTeardown: runtimeTeardown
            ),
            splitGroupReset: TabStartupSplitGroupResetTransaction(
                store: state.splitGroups,
                mutations: splitMutations
            ),
            regularCollectionReset: TabStartupRegularCollectionResetTransaction(
                state: state,
                structuralMutations: structuralMutations,
                persistence: manager.structuralPersistence
            ),
            transientStateReset: TabStartupTransientStateResetTransaction(
                lazyRestore: lazyRestore,
                liveShortcutRetirement: liveShortcutRetirement
            )
        )

        self.manager = manager
        self.merge = merge
        self.startupReset = startupReset
        self.membership = membership
        self.structuralLookup = structuralLookup
        connection.attach(TestRuntimePorts.inactive)
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
