import Combine
import Foundation
import Observation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class TabStructuralCollectionMutationOwnerTests: XCTestCase {
    func testSetTabsSortsAndRunsStructuralSideEffects() throws {
        let spaceId = UUID()
        let previousTab = Self.makeTab(index: 0)
        let laterTab = Self.makeTab(index: 2)
        let earlierTab = Self.makeTab(index: 1)
        let harness = try Harness()
        harness.tabsBySpace[spaceId] = [previousTab]
        let owner = harness.makeOwner()
        var callbackCount = 0
        var callbackSawTerminalLookup = false
        let callback = harness.manager.objectWillChange.sink { _ in
            callbackCount += 1
            callbackSawTerminalLookup =
                harness.manager.tabCollectionMembershipOwner.tab(
                    for: previousTab.id
                ) == nil
                && harness.manager.tabCollectionMembershipOwner.tab(
                    for: earlierTab.id
                ) === earlierTab
                && harness.manager.tabCollectionMembershipOwner.tab(
                    for: laterTab.id
                ) === laterTab
        }

        owner.setTabs([laterTab, earlierTab], for: spaceId)

        XCTAssertEqual(harness.tabsBySpace[spaceId]?.map(\.id), [earlierTab.id, laterTab.id])
        XCTAssertEqual(
            harness.dirtySet.dirtyTabIds,
            [earlierTab.id, laterTab.id]
        )
        XCTAssertEqual(harness.dirtySet.deletedTabIds, [previousTab.id])
        XCTAssertNil(
            harness.manager.tabCollectionMembershipOwner.tab(for: previousTab.id)
        )
        XCTAssertIdentical(
            harness.manager.tabCollectionMembershipOwner.tab(for: earlierTab.id),
            earlierTab
        )
        XCTAssertIdentical(
            harness.manager.tabCollectionMembershipOwner.tab(for: laterTab.id),
            laterTab
        )
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(callbackSawTerminalLookup)
        XCTAssertEqual(harness.publishCount, 1)
        withExtendedLifetime(callback) {}
    }

    func testSetPinnedTabsSyncsAllShortcutCollectionsAndPublishes() throws {
        let profileId = UUID()
        let spaceId = UUID()
        let previousPin = Self.makePin(role: .essential, profileId: profileId, index: 0)
        let currentPin = Self.makePin(role: .essential, profileId: profileId, index: 1)
        let spacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let harness = try Harness()
        harness.pinnedByProfile[profileId] = [previousPin]
        harness.spacePinnedShortcuts[spaceId] = [spacePin]
        let owner = harness.makeOwner()

        owner.setPinnedTabs([currentPin], for: profileId)

        XCTAssertEqual(harness.pinnedByProfile[profileId]?.map(\.id), [currentPin.id])
        XCTAssertEqual(harness.dirtySet.dirtyTabIds, [currentPin.id])
        XCTAssertEqual(harness.dirtySet.deletedTabIds, [previousPin.id])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testSetFoldersRunsStructuralSideEffects() throws {
        let spaceId = UUID()
        let previousFolder = Self.makeFolder(name: "Previous", spaceId: spaceId, index: 0)
        let currentFolder = Self.makeFolder(name: "Current", spaceId: spaceId, index: 1)
        let harness = try Harness()
        harness.foldersBySpace[spaceId] = [previousFolder]
        let owner = harness.makeOwner()

        owner.setFolders([currentFolder], for: spaceId)

        XCTAssertEqual(harness.foldersBySpace[spaceId]?.map(\.id), [currentFolder.id])
        XCTAssertEqual(harness.dirtySet.dirtyFolderIds, [currentFolder.id])
        XCTAssertEqual(harness.dirtySet.deletedFolderIds, [previousFolder.id])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testSetSpacePinnedShortcutsSyncsAllShortcutCollectionsAndPublishes() throws {
        let profileId = UUID()
        let spaceId = UUID()
        let profilePin = Self.makePin(role: .essential, profileId: profileId, index: 0)
        let previousSpacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let currentSpacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 1)
        let harness = try Harness()
        harness.pinnedByProfile[profileId] = [profilePin]
        harness.spacePinnedShortcuts[spaceId] = [previousSpacePin]
        let owner = harness.makeOwner()

        owner.setSpacePinnedShortcuts([currentSpacePin], for: spaceId)

        XCTAssertEqual(harness.spacePinnedShortcuts[spaceId]?.map(\.id), [currentSpacePin.id])
        XCTAssertEqual(harness.dirtySet.dirtyTabIds, [currentSpacePin.id])
        XCTAssertEqual(harness.dirtySet.deletedTabIds, [previousSpacePin.id])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testRejectedReversibleBatchRestoresCollectionsWithoutEffects() throws {
        let spaceID = UUID()
        let profileID = UUID()
        let originalTab = Self.makeTab(index: 0)
        let originalPin = Self.makePin(
            role: .essential,
            profileId: profileID,
            index: 0
        )
        let originalSpacePin = Self.makePin(
            role: .spacePinned,
            spaceId: spaceID,
            index: 0
        )
        let harness = try Harness()
        harness.tabsBySpace[spaceID] = [originalTab]
        harness.pinnedByProfile[profileID] = [originalPin]
        harness.spacePinnedShortcuts[spaceID] = [originalSpacePin]
        let owner = harness.makeOwner()

        let committed = owner.withReversibleSideEffects {
            owner.setTabs([Self.makeTab(index: 1)], for: spaceID)
            owner.setPinnedTabs([], for: profileID)
            owner.setSpacePinnedShortcuts([], for: spaceID)
            return false
        }

        XCTAssertFalse(committed)
        XCTAssertIdentical(harness.tabsBySpace[spaceID]?.first, originalTab)
        XCTAssertIdentical(harness.pinnedByProfile[profileID]?.first, originalPin)
        XCTAssertIdentical(
            harness.spacePinnedShortcuts[spaceID]?.first,
            originalSpacePin
        )
        XCTAssertTrue(harness.dirtySet.isEmpty)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.tabsSnapshotPublishCount, 0)
    }

    func testPreparedAggregateDefersEffectsUntilTerminalPublish() throws {
        let spaceID = UUID()
        let source = Self.makeTab(index: 0)
        let target = Self.makeTab(index: 1)
        let harness = try Harness()
        harness.tabsBySpace[spaceID] = [source]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        owner.setTabs([target], for: spaceID)
        XCTAssertTrue(aggregate.stage())

        XCTAssertIdentical(harness.tabsBySpace[spaceID]?.first, target)
        XCTAssertTrue(harness.dirtySet.isEmpty)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertTrue(aggregate.isCurrent())

        XCTAssertTrue(aggregate.publish())
        XCTAssertEqual(harness.dirtySet.dirtyTabIds, [target.id])
        XCTAssertEqual(harness.dirtySet.deletedTabIds, [source.id])
        XCTAssertEqual(harness.announceCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testAggregateFirstCallbackSeesEveryStructuralEffect() throws {
        let spaceID = UUID()
        let profileID = UUID()
        let sourceTab = Self.makeTab(index: 0)
        let targetTab = Self.makeTab(index: 1)
        let sourceFolder = Self.makeFolder(
            name: "Source",
            spaceId: spaceID,
            index: 0
        )
        let targetFolder = Self.makeFolder(
            name: "Target",
            spaceId: spaceID,
            index: 1
        )
        let sourcePin = Self.makePin(
            role: .essential,
            profileId: profileID,
            index: 0
        )
        let targetPin = Self.makePin(
            role: .essential,
            profileId: profileID,
            index: 1
        )
        let harness = try Harness()
        harness.tabsBySpace[spaceID] = [sourceTab]
        harness.foldersBySpace[spaceID] = [sourceFolder]
        harness.pinnedByProfile[profileID] = [sourcePin]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        owner.setTabs([targetTab], for: spaceID)
        owner.setFolders([targetFolder], for: spaceID)
        owner.setPinnedTabs([targetPin], for: profileID)
        XCTAssertTrue(aggregate.stage())

        var callbackCount = 0
        var callbackSawTerminalState = false
        let callback = harness.manager.objectWillChange.sink { _ in
            callbackCount += 1
            callbackSawTerminalState =
                harness.manager.tabCollectionMembershipOwner.tab(
                    for: targetTab.id
                ) === targetTab
                && harness.manager.tabCollectionMembershipOwner.tab(
                    for: sourceTab.id
                ) == nil
                && harness.foldersBySpace[spaceID]?.first === targetFolder
                && harness.pinnedByProfile[profileID]?.first === targetPin
                && harness.dirtySet.dirtyTabIds == [targetTab.id, targetPin.id]
                && harness.dirtySet.deletedTabIds == [sourceTab.id, sourcePin.id]
                && harness.dirtySet.dirtyFolderIds == [targetFolder.id]
                && harness.dirtySet.deletedFolderIds == [sourceFolder.id]
        }

        XCTAssertTrue(aggregate.publish())

        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(callbackSawTerminalState)
        XCTAssertEqual(harness.publishCount, 1)
        withExtendedLifetime(callback) {}
    }

    func testCancellingUnmodifiedPreparedAggregatePerformsNoWrites() throws {
        let harness = try Harness()
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        XCTAssertTrue(aggregate.rollback())

        XCTAssertTrue(harness.tabsBySpace.isEmpty)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.tabsSnapshotPublishCount, 0)
        let next = try XCTUnwrap(owner.prepareAggregate())
        XCTAssertTrue(next.rollback())
        XCTAssertTrue(harness.tabsBySpace.isEmpty)
    }

    func testPreparedAggregateRollbackRestoresUnpublishedSnapshot() throws {
        let spaceID = UUID()
        let source = Self.makeTab(index: 0)
        let target = Self.makeTab(index: 1)
        let harness = try Harness()
        harness.tabsBySpace[spaceID] = [source]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        owner.setTabs([target], for: spaceID)
        XCTAssertTrue(aggregate.stage())
        XCTAssertTrue(aggregate.rollback())

        XCTAssertIdentical(harness.tabsBySpace[spaceID]?.first, source)
        XCTAssertTrue(harness.dirtySet.isEmpty)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.tabsSnapshotPublishCount, 0)
    }

    func testFolderPlacementPublishesOnlyThroughStructuralSnapshot() throws {
        let spaceID = UUID()
        let folder = Self.makeFolder(
            name: "Folder",
            spaceId: spaceID,
            index: 0
        )
        let harness = try Harness()
        harness.foldersBySpace[spaceID] = [folder]
        let owner = harness.makeOwner()
        let observation = FolderPlacementObservationOracle()
        withObservationTracking {
            _ = folder.spaceId
            _ = folder.parentFolderId
            _ = folder.index
        } onChange: {
            MainActor.assumeIsolated { observation.count += 1 }
        }

        let rejected = try XCTUnwrap(owner.prepareAggregate())
        folder.installPlacement(TabFolderPlacement(
            spaceID: spaceID,
            parentFolderID: UUID(),
            index: 4
        ))
        owner.setFolders([folder], for: spaceID)
        XCTAssertTrue(rejected.stage())
        XCTAssertEqual(observation.count, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertTrue(rejected.rollback())
        XCTAssertEqual(folder.placementSnapshot, TabFolderPlacement(
            spaceID: spaceID,
            parentFolderID: nil,
            index: 0
        ))
        XCTAssertEqual(observation.count, 0)
        XCTAssertEqual(harness.publishCount, 0)

        let committed = try XCTUnwrap(owner.prepareAggregate())
        let target = TabFolderPlacement(
            spaceID: spaceID,
            parentFolderID: UUID(),
            index: 2
        )
        folder.installPlacement(target)
        owner.setFolders([folder], for: spaceID)
        XCTAssertTrue(committed.stage())
        XCTAssertTrue(committed.publish())
        XCTAssertEqual(folder.placementSnapshot, target)
        XCTAssertEqual(observation.count, 0)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.dirtySet.dirtyFolderIds, [folder.id])
        XCTAssertEqual(harness.foldersBySpace[spaceID]?.first?.placementSnapshot, target)
    }

    func testPreparedAggregateTerminalDrainKeepsRawTargetWithoutEffects()
        throws {
        let spaceID = UUID()
        let source = Self.makeTab(index: 0)
        let target = Self.makeTab(index: 1)
        let harness = try Harness()
        harness.tabsBySpace[spaceID] = [source]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        owner.setTabs([target], for: spaceID)
        XCTAssertTrue(aggregate.stage())
        XCTAssertTrue(aggregate.canAbandonForTerminalDrain())
        aggregate.abandonForTerminalDrain()

        XCTAssertIdentical(harness.tabsBySpace[spaceID]?.first, target)
        XCTAssertTrue(harness.dirtySet.isEmpty)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.tabsSnapshotPublishCount, 0)

        let next = try XCTUnwrap(owner.prepareAggregate())
        XCTAssertTrue(next.rollback())
    }

    private static func makeTab(index: Int) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(index)")!,
            name: "Tab \(index)",
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }

    private static func makePin(
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: "Pin \(index)"
        )
    }

    private static func makeFolder(name: String, spaceId: UUID, index: Int) -> TabFolder {
        TabFolder(name: name, spaceId: spaceId, index: index)
    }

    @MainActor
    private final class Harness {
        let manager: TabManager
        private var cancellables = Set<AnyCancellable>()
        private(set) var announceCount = 0
        private(set) var tabsSnapshotPublishCount = 0

        init() throws {
            manager = try makeInMemoryTabManager()
            manager.objectWillChange.sink { [weak self] _ in
                self?.announceCount += 1
            }.store(in: &cancellables)
            manager.regularTabCollectionStateOwner.tabsBySpacePublisher.sink {
                [weak self] _ in self?.tabsSnapshotPublishCount += 1
            }.store(in: &cancellables)
        }

        var tabsBySpace: [UUID: [Tab]] {
            get { manager.regularTabCollectionStateOwner.tabsBySpaceSnapshot() }
            set {
                manager.regularTabCollectionStateOwner.replaceTabsBySpace(
                    newValue,
                    publish: false
                )
                manager.structuralLookupCoordinator.rebuild()
            }
        }

        var foldersBySpace: [UUID: [TabFolder]] {
            get { manager.folderCollectionStateOwner.foldersBySpaceSnapshot() }
            set { manager.folderCollectionStateOwner.replaceFoldersBySpace(newValue) }
        }

        var pinnedByProfile: [UUID: [ShortcutPin]] {
            get { manager.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() }
            set { manager.shortcutPinCollectionStateOwner.replacePinnedByProfile(newValue) }
        }

        var spacePinnedShortcuts: [UUID: [ShortcutPin]] {
            get { manager.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot() }
            set { manager.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts(newValue) }
        }

        var dirtySet: TabStructuralDirtySet {
            manager.structuralPersistence.dirtySet
        }

        var publishCount: UInt64 {
            manager.structuralLookupCoordinator.mutationRevision
        }

        func makeOwner() -> TabStructuralCollectionMutationOwner {
            manager.structuralCollectionMutationOwner
        }
    }
}

@MainActor
private final class FolderPlacementObservationOracle {
    var count = 0
}

@MainActor
final class TabStructuralInstallOwnerTests: XCTestCase {
    func testInstallReplacesAllCollectionsAndRunsSingleStructuralSideEffectPass() throws {
        let harness = Harness()
        let owner = harness.makeOwner()
        let space = Space(name: "Workspace")
        let tab = Self.makeTab(index: 0, spaceId: space.id)
        let siblingTabId = UUID()
        let folder = TabFolder(name: "Folder", spaceId: space.id, index: 0)
        let essentialPin = Self.makePin(role: .essential, profileId: UUID(), index: 0)
        let spacePin = Self.makePin(role: .spacePinned, spaceId: space.id, index: 0)
        let pendingPin = Self.makePin(role: .essential, index: 1)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(tab.id), .regularTab(siblingTabId)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )

        owner.install(
            spaces: [space],
            tabsBySpace: [space.id: [tab]],
            foldersBySpace: [space.id: [folder]],
            pinnedByProfile: [essentialPin.profileId!: [essentialPin]],
            spacePinnedShortcuts: [space.id: [spacePin]],
            pendingPinnedWithoutProfile: [pendingPin],
            splitGroups: [group],
            currentSpace: space,
            currentTab: tab
        )

        XCTAssertEqual(harness.transactionCount, 1)
        XCTAssertEqual(harness.objectWillChangeCount, 1)
        XCTAssertEqual(harness.spaces.map(\.id), [space.id])
        XCTAssertEqual(harness.tabsBySpace[space.id]?.map(\.id), [tab.id])
        XCTAssertEqual(harness.foldersBySpace[space.id]?.map(\.id), [folder.id])
        XCTAssertEqual(harness.splitGroups.map(\.id), [group.id])
        XCTAssertEqual(harness.pinnedByProfile[essentialPin.profileId!]?.map(\.id), [essentialPin.id])
        XCTAssertEqual(harness.spacePinnedShortcuts[space.id]?.map(\.id), [spacePin.id])
        XCTAssertEqual(harness.pendingPinnedWithoutProfile.map(\.id), [pendingPin.id])
        XCTAssertEqual(harness.currentSpace?.id, space.id)
        XCTAssertEqual(harness.currentTab?.id, tab.id)
        XCTAssertEqual(harness.syncedShortcutPinIds, [[essentialPin.id, spacePin.id]])
        XCTAssertEqual(harness.rebuildTabLookupCount, 1)
        XCTAssertEqual(harness.markSnapshotCacheDirtyCount, 1)
        XCTAssertEqual(harness.resetStructuralDirtySetCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testInstallRestoredCollectionsDoesNotResetStructuralDirtyState() {
        let harness = Harness()
        let owner = harness.makeOwner()
        let space = Space(name: "Restored")
        let restoredState = TabRestoreRuntimeState(
            spaces: [space],
            tabsBySpace: [space.id: []],
            foldersBySpace: [:],
            pinnedByProfile: [:],
            pendingPinnedWithoutProfile: [],
            spacePinnedShortcuts: [:],
            repairReasons: []
        )

        owner.installRestoredCollections(
            restoredState,
            splitGroups: [],
            currentSpace: space,
            currentTab: nil
        )

        XCTAssertEqual(harness.transactionCount, 1)
        XCTAssertEqual(harness.spaces.map(\.id), [space.id])
        XCTAssertEqual(harness.currentSpace?.id, space.id)
        XCTAssertEqual(harness.resetStructuralDirtySetCount, 0)
        XCTAssertEqual(harness.publishCount, 1)
    }

    private static func makeTab(index: Int, spaceId: UUID) -> Tab {
        Tab(
            url: URL(string: "https://example.com/install-\(index)")!,
            name: "Install \(index)",
            spaceId: spaceId,
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }

    private static func makePin(
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            launchURL: URL(string: "https://example.com/install-pin-\(index)")!,
            title: "Install Pin \(index)"
        )
    }

    @MainActor
    private final class Harness {
        var transactionCount = 0
        var objectWillChangeCount = 0
        var spaces: [Space] = []
        var tabsBySpace: [UUID: [Tab]] = [:]
        var foldersBySpace: [UUID: [TabFolder]] = [:]
        var splitGroups: [SplitGroup] = []
        var pinnedByProfile: [UUID: [ShortcutPin]] = [:]
        var spacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        var pendingPinnedWithoutProfile: [ShortcutPin] = []
        var currentSpace: Space?
        var currentTab: Tab?
        var syncedShortcutPinIds: [[UUID]] = []
        var rebuildTabLookupCount = 0
        var markSnapshotCacheDirtyCount = 0
        var resetStructuralDirtySetCount = 0
        var publishCount = 0

        func makeOwner() -> TabStructuralInstallOwner {
            TabStructuralInstallOwner(
                dependencies: TabStructuralInstallOwner.Dependencies(
                    withStructuralUpdateTransaction: {
                        self.transactionCount += 1
                        $0()
                    },
                    objectWillChange: {
                        self.objectWillChangeCount += 1
                    },
                    replaceSpaces: {
                        self.spaces = $0
                    },
                    replaceTabsBySpace: {
                        self.tabsBySpace = $0
                    },
                    replaceFoldersBySpace: {
                        self.foldersBySpace = $0
                    },
                    replaceSplitGroups: {
                        self.splitGroups = $0
                    },
                    replaceShortcutPins: {
                        self.pinnedByProfile = $0
                        self.spacePinnedShortcuts = $1
                        self.pendingPinnedWithoutProfile = $2
                    },
                    replaceCurrentSpace: {
                        self.currentSpace = $0
                    },
                    replaceCurrentTab: {
                        self.currentTab = $0
                    },
                    syncShortcutPins: {
                        self.syncedShortcutPinIds.append($0.map(\.id))
                    },
                    rebuildTabLookup: {
                        self.rebuildTabLookupCount += 1
                    },
                    markSnapshotCacheDirty: {
                        self.markSnapshotCacheDirtyCount += 1
                    },
                    resetStructuralDirtySet: {
                        self.resetStructuralDirtySetCount += 1
                    },
                    requestStructuralPublish: {
                        self.publishCount += 1
                    }
                )
            )
        }
    }
}
