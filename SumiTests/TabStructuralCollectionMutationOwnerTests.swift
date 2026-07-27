import Combine
import Foundation
import Observation
import SumiDomain
import SumiWebRuntime
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
        let callback = harness.changes.sink { _ in
            callbackCount += 1
            callbackSawTerminalLookup =
                harness.membership.tab(
                    for: previousTab.id
                ) == nil
                && harness.membership.tab(
                    for: earlierTab.id
                ) === earlierTab
                && harness.membership.tab(
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
            harness.membership.tab(for: previousTab.id)
        )
        XCTAssertIdentical(
            harness.membership.tab(for: earlierTab.id),
            earlierTab
        )
        XCTAssertIdentical(
            harness.membership.tab(for: laterTab.id),
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

    func testRemovePinnedTabsDeletesProfileEntryAndPublishes() throws {
        let profileId = UUID()
        let pin = Self.makePin(
            role: .essential,
            profileId: profileId,
            index: 0
        )
        let harness = try Harness()
        harness.pinnedByProfile[profileId] = [pin]
        let owner = harness.makeOwner()

        let removed = owner.removePinnedTabs(for: profileId)

        XCTAssertEqual(removed?.map(\.id), [pin.id])
        XCTAssertNil(harness.pinnedByProfile[profileId])
        XCTAssertEqual(harness.dirtySet.deletedTabIds, [pin.id])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testRemoveMissingPinnedTabsPerformsNoMutation() throws {
        let harness = try Harness()
        let owner = harness.makeOwner()

        XCTAssertNil(owner.removePinnedTabs(for: UUID()))

        XCTAssertTrue(harness.pinnedByProfile.isEmpty)
        XCTAssertTrue(harness.dirtySet.isEmpty)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
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

    func testRejectedReversibleBatchPublishesRestoredFolderExpansion() throws {
        let spaceID = UUID()
        let folder = Self.makeFolder(
            name: "Folder",
            spaceId: spaceID,
            index: 0
        )
        let harness = try Harness()
        harness.foldersBySpace[spaceID] = [folder]
        let owner = harness.makeOwner()

        let committed = owner.withReversibleSideEffects {
            folder.isOpen = true
            owner.setFolders([folder], for: spaceID)
            return false
        }

        XCTAssertFalse(committed)
        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(harness.expansionChanges.count, 1)
        XCTAssertEqual(harness.expansionChanges.first?.spaceID, spaceID)
        XCTAssertEqual(
            harness.expansionChanges.first?.expansionByFolderID,
            [folder.id: false]
        )
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
        let callback = harness.changes.sink { _ in
            callbackCount += 1
            callbackSawTerminalState =
                harness.membership.tab(
                    for: targetTab.id
                ) === targetTab
                && harness.membership.tab(
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

    func testMutationAfterStageInvalidatesAndReleasesSealedAggregate() throws {
        let stagedProfileID = UUID()
        let foreignProfileID = UUID()
        let stagedPin = Self.makePin(
            role: .essential,
            profileId: stagedProfileID,
            index: 0
        )
        let foreignPin = Self.makePin(
            role: .essential,
            profileId: foreignProfileID,
            index: 0
        )
        let favicon = StructuralMutationFaviconOracle()
        let harness = try Harness(faviconService: favicon)
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())
        owner.setPinnedTabs([stagedPin], for: stagedProfileID)
        XCTAssertTrue(aggregate.stage())
        var availabilityCount = 0
        let observationID = try XCTUnwrap(owner.observeNextAvailability {
            availabilityCount += 1
        })

        owner.setPinnedTabs([foreignPin], for: foreignProfileID)

        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(favicon.syncedPinIDs, [[foreignPin.id]])
        XCTAssertFalse(aggregate.publish())
        XCTAssertEqual(availabilityCount, 1)
        XCTAssertFalse(owner.isAvailabilityObservationActive)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertIdentical(
            harness.pinnedByProfile[foreignProfileID]?.first,
            foreignPin
        )
        XCTAssertNil(harness.pinnedByProfile[stagedProfileID]?.first)
        let next = try XCTUnwrap(owner.prepareAggregate())
        XCTAssertTrue(next.rollback())
        owner.cancelAvailabilityObservation(observationID)
    }

    func testForeignMutationRestoresSourceOnlyFolderKeyAndReceipt() throws {
        let sourceSpaceID = UUID()
        let foreignProfileID = UUID()
        let sourceFolder = Self.makeFolder(
            name: "Source",
            spaceId: sourceSpaceID,
            index: 0
        )
        let sourceOpenState = sourceFolder.isOpen
        let foreignPin = Self.makePin(
            role: .essential,
            profileId: foreignProfileID,
            index: 0
        )
        let harness = try Harness()
        harness.foldersBySpace = [sourceSpaceID: [sourceFolder]]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        harness.foldersBySpace = [:]
        XCTAssertTrue(aggregate.stage())
        owner.setPinnedTabs([foreignPin], for: foreignProfileID)

        XCTAssertFalse(aggregate.publish())
        XCTAssertIdentical(
            harness.foldersBySpace[sourceSpaceID]?.first,
            sourceFolder
        )
        XCTAssertEqual(sourceFolder.name, "Source")
        XCTAssertEqual(sourceFolder.isOpen, sourceOpenState)
        XCTAssertIdentical(
            harness.pinnedByProfile[foreignProfileID]?.first,
            foreignPin
        )
        let next = try XCTUnwrap(owner.prepareAggregate())
        XCTAssertTrue(next.rollback())
    }

    func testForeignFolderPropertyMutationPreventsSourceOnlyRestore() throws {
        let sourceSpaceID = UUID()
        let foreignProfileID = UUID()
        let sourceFolder = Self.makeFolder(
            name: "Source",
            spaceId: sourceSpaceID,
            index: 0
        )
        let foreignPin = Self.makePin(
            role: .essential,
            profileId: foreignProfileID,
            index: 0
        )
        let harness = try Harness()
        harness.foldersBySpace = [sourceSpaceID: [sourceFolder]]
        let owner = harness.makeOwner()
        let aggregate = try XCTUnwrap(owner.prepareAggregate())

        harness.foldersBySpace = [:]
        XCTAssertTrue(aggregate.stage())
        sourceFolder.name = "Foreign"

        owner.setPinnedTabs([foreignPin], for: foreignProfileID)

        XCTAssertFalse(aggregate.publish())
        XCTAssertNil(harness.foldersBySpace[sourceSpaceID])
        XCTAssertEqual(sourceFolder.name, "Foreign")
        XCTAssertIdentical(
            harness.pinnedByProfile[foreignProfileID]?.first,
            foreignPin
        )
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
        let changes: ObservableObjectPublisher
        let membership: TabCollectionMembershipOwner
        private let state: TabStateStore
        private let lookup: TabStructuralLookupCoordinator
        private let persistence: TabStructuralPersistenceService
        private let owner: TabStructuralCollectionMutationOwner
        private let retainedDatabase: SumiDatabase
        private var cancellables = Set<AnyCancellable>()
        private(set) var announceCount = 0
        private(set) var tabsSnapshotPublishCount = 0
        private(set) var expansionChanges: [TabFolderExpansionChange] = []

        init(
            faviconService: (any BrowserFaviconServicing)? = nil
        ) throws {
            let container = try makeInMemoryStartupDatabase()
            retainedDatabase = container
            let state = TabStateStore()
            self.state = state
            let eventBus = TabStructureEventBus()
            let lookup = TabStructuralLookupCoordinator(
                eventBus: eventBus,
                stateStore: state
            )
            self.lookup = lookup
            let writes = TabStoreWriteExecutor(database: container)
            let persistence = TabStructuralPersistenceService(
                structuralStore: TabStructuralSnapshotStore(writes: writes),
                selectionStore: TabSelectionStore(writes: writes),
                runtimeStateCoalescer: RuntimeStateCoalescer { _ in },
                state: state
            )
            self.persistence = persistence
            let changes = ObservableObjectPublisher()
            self.changes = changes
            let publisher = TabStructuralMutationPublisher(
                persistence: persistence,
                faviconService: faviconService
                    ?? TabDependencyIsolationDefaults.faviconService,
                lookup: lookup,
                changes: changes,
                regularTabs: state.regularTabs
            )
            owner = TabStructuralCollectionMutationOwner(
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
                publisher: publisher
            )
            let runtimeConnection = TabRuntimePortConnection()
            membership = TabCollectionMembershipOwner(
                structuralLookupOwner: lookup.lookupOwner,
                state: state,
                runtimePreparation: TabRuntimePreparationOwner(
                    runtimeConnection: runtimeConnection
                ),
                runtimeConnection: runtimeConnection
            )
            changes.sink { [weak self] _ in
                self?.announceCount += 1
            }.store(in: &cancellables)
            state.regularTabs.tabsBySpacePublisher.sink {
                [weak self] _ in self?.tabsSnapshotPublishCount += 1
            }.store(in: &cancellables)
            eventBus.folderExpansionChangesPublisher.sink {
                [weak self] change in self?.expansionChanges.append(change)
            }.store(in: &cancellables)
        }

        var tabsBySpace: [UUID: [Tab]] {
            get { state.regularTabs.tabsBySpaceSnapshot() }
            set {
                state.regularTabs.replaceTabsBySpace(
                    newValue,
                    publish: false
                )
                lookup.rebuild()
            }
        }

        var foldersBySpace: [UUID: [TabFolder]] {
            get { state.folders.foldersBySpaceSnapshot() }
            set { state.folders.replaceFoldersBySpace(newValue) }
        }

        var pinnedByProfile: [UUID: [ShortcutPin]] {
            get { state.shortcutPins.pinnedByProfileSnapshot() }
            set { state.shortcutPins.replacePinnedByProfile(newValue) }
        }

        var spacePinnedShortcuts: [UUID: [ShortcutPin]] {
            get { state.shortcutPins.spacePinnedShortcutsSnapshot() }
            set { state.shortcutPins.replaceSpacePinnedShortcuts(newValue) }
        }

        var dirtySet: TabStructuralDirtySet {
            persistence.dirtySet
        }

        var publishCount: UInt64 {
            lookup.mutationRevision
        }

        func makeOwner() -> TabStructuralCollectionMutationOwner {
            owner
        }
    }
}

@MainActor
private final class FolderPlacementObservationOracle {
    var count = 0
}

@MainActor
private final class StructuralMutationFaviconOracle: BrowserFaviconServicing {
    private(set) var syncedPinIDs: [[UUID]] = []

    func partition(profile: Profile?) -> SumiFaviconPartition {
        .regular(profile?.id)
    }

    func invalidateSite(domain _: String, profile _: Profile?) {}

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        syncedPinIDs.append(pins.map(\.id))
    }

    func syncBookmarks(
        _: [SumiBookmark],
        partition _: SumiFaviconPartition
    ) {}

    func clearFaviconPartition(for _: Profile) {}

#if DEBUG
    func drainRuntimeTasksForTests(cancel _: Bool) async {}
#endif
}

@MainActor
final class TabStructuralInstallOwnerTests: XCTestCase {
    func testInstallReplacesAllCollectionsAndRunsSingleStructuralSideEffectPass() throws {
        let harness = try Harness(
            profileReferenceAdmission: try makeAdmissionLedger()
        )
        let owner = harness.makeOwner()
        harness.persistence.markSplitGroupsStructurallyDirty()
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
        XCTAssertEqual(harness.favicon.syncedPinIDs, [[essentialPin.id, spacePin.id]])
        XCTAssertTrue(
            harness.lookup.lookupOwner.containsExact(tab)
        )
        XCTAssertTrue(harness.persistence.dirtySet.isEmpty)
        XCTAssertEqual(harness.publishCount, 2)
        XCTAssertEqual(harness.expansionChanges.count, 1)
        XCTAssertEqual(harness.expansionChanges.first?.spaceID, space.id)
        XCTAssertEqual(
            harness.expansionChanges.first?.expansionByFolderID,
            [folder.id: false]
        )
    }

    func testInstallRestoredCollectionsDoesNotResetStructuralDirtyState() throws {
        let harness = try Harness(
            profileReferenceAdmission: try makeAdmissionLedger()
        )
        let owner = harness.makeOwner()
        harness.persistence.markSplitGroupsStructurallyDirty()
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
            currentTab: nil,
            admitted: { true },
            onInstalled: {}
        )

        XCTAssertEqual(harness.spaces.map(\.id), [space.id])
        XCTAssertEqual(harness.currentSpace?.id, space.id)
        XCTAssertFalse(harness.persistence.dirtySet.isEmpty)
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testUnavailableAdmissionRejectsInstallBeforeStructuralTransaction() throws {
        let harness = try Harness(
            profileReferenceAdmission: .failClosed()
        )
        let owner = harness.makeOwner()
        let profileID = UUID()
        let space = Space(name: "Blocked", profileId: profileID)
        let tab = Self.makeTab(index: 0, spaceId: space.id)
        tab.profileId = profileID

        XCTAssertFalse(owner.install(
            spaces: [space],
            tabsBySpace: [space.id: [tab]],
            foldersBySpace: [:],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: tab
        ))
        XCTAssertEqual(harness.objectWillChangeCount, 0)
        XCTAssertTrue(harness.spaces.isEmpty)
        XCTAssertTrue(harness.tabsBySpace.isEmpty)
        XCTAssertEqual(harness.publishCount, 0)
    }

    func testExternalLeaseMustCoverEveryCandidateProfileBeforeMutation() throws {
        let admission = try makeAdmissionLedger()
        let harness = try Harness(profileReferenceAdmission: admission)
        let owner = harness.makeOwner()
        let profileID = UUID()
        let space = Space(name: "Uncovered", profileId: profileID)
        let lease = try admission.beginReferenceMutation(to: [])
        defer { XCTAssertTrue(admission.endReferenceMutation(lease)) }

        XCTAssertFalse(owner.install(
            spaces: [space],
            tabsBySpace: [:],
            foldersBySpace: [:],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: nil,
            referenceMutationLease: lease
        ))
        XCTAssertEqual(harness.objectWillChangeCount, 0)
        XCTAssertTrue(harness.spaces.isEmpty)
        XCTAssertEqual(harness.publishCount, 0)
    }

    private func makeAdmissionLedger() throws -> ProfileReferenceAdmissionLedger {
        let container = try makeInMemoryStartupDatabase()
        return try ProfileReferenceAdmissionLedger(database: container)
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
        let state: TabStateStore
        let lookup: TabStructuralLookupCoordinator
        let persistence: TabStructuralPersistenceService
        let favicon: StructuralMutationFaviconOracle
        let profileReferenceAdmission: ProfileReferenceAdmissionLedger
        private let container: AnyObject
        private let changes: ObservableObjectPublisher
        private let owner: TabStructuralInstallOwner
        private var cancellables = Set<AnyCancellable>()
        var objectWillChangeCount = 0
        private(set) var expansionChanges: [TabFolderExpansionChange] = []

        init(profileReferenceAdmission: ProfileReferenceAdmissionLedger) throws {
            let container = try makeInMemoryStartupDatabase()
            self.container = container
            self.profileReferenceAdmission = profileReferenceAdmission
            let favicon = StructuralMutationFaviconOracle()
            self.favicon = favicon
            let changes = ObservableObjectPublisher()
            self.changes = changes
            let state = TabStateStore()
            self.state = state
            let eventBus = TabStructureEventBus()
            let lookup = TabStructuralLookupCoordinator(
                eventBus: eventBus,
                stateStore: state
            )
            self.lookup = lookup
            let writes = TabStoreWriteExecutor(database: container)
            let persistence = TabStructuralPersistenceService(
                structuralStore: TabStructuralSnapshotStore(writes: writes),
                selectionStore: TabSelectionStore(writes: writes),
                runtimeStateCoalescer: RuntimeStateCoalescer { _ in },
                state: state
            )
            self.persistence = persistence
            owner = TabStructuralInstallOwner(
                state: state,
                structuralLookup: lookup,
                persistence: persistence,
                publication: TabStructuralInstallPublication(
                    changes: changes,
                    faviconService: favicon
                ),
                profileReferenceAdmission: profileReferenceAdmission
            )
            changes.sink { [weak self] _ in
                self?.objectWillChangeCount += 1
            }.store(in: &cancellables)
            eventBus.folderExpansionChangesPublisher.sink {
                [weak self] change in self?.expansionChanges.append(change)
            }.store(in: &cancellables)
        }

        func makeOwner() -> TabStructuralInstallOwner {
            owner
        }

        var spaces: [Space] { state.spaces.spaces }
        var tabsBySpace: [UUID: [Tab]] {
            state.regularTabs.tabsBySpaceSnapshot()
        }
        var foldersBySpace: [UUID: [TabFolder]] {
            state.folders.foldersBySpaceSnapshot()
        }
        var splitGroups: [SplitGroup] { state.splitGroups.groups }
        var pinnedByProfile: [UUID: [ShortcutPin]] {
            state.shortcutPins.pinnedByProfileSnapshot()
        }
        var spacePinnedShortcuts: [UUID: [ShortcutPin]] {
            state.shortcutPins.spacePinnedShortcutsSnapshot()
        }
        var pendingPinnedWithoutProfile: [ShortcutPin] {
            state.shortcutPins.pendingPinnedWithoutProfileSnapshot()
        }
        var currentSpace: Space? { state.spaces.currentSpace }
        var currentTab: Tab? { state.selection.currentTab }
        var publishCount: UInt64 { lookup.mutationRevision }
    }
}
