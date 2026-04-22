import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralPersistenceTests: XCTestCase {
    func testIncrementalAddAndRemoveRegularTabPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Work", profileId: UUID())
        let tab = tabManager.createNewTab(in: space, activate: true)

        let didPersistAdd = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistAdd)

        var context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.spaceId, space.id)
        XCTAssertFalse(storedTab.isPinned)
        XCTAssertFalse(storedTab.isSpacePinned)

        tabManager.removeTab(tab.id)
        let didPersistRemove = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistRemove)

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
    }

    func testIncrementalFolderRelationshipPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.createNewTab(url: "https://example.com/docs", in: space, activate: true)

        tabManager.moveTabToFolder(tab: tab, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)

        let didPersistFolderMove = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistFolderMove)

        var context = ModelContext(container)
        let storedFolder = try XCTUnwrap(fetchFolder(folder.id, in: context))
        XCTAssertEqual(storedFolder.spaceId, space.id)

        var storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertTrue(storedPin.isSpacePinned)
        XCTAssertEqual(storedPin.folderId, folder.id)

        tabManager.deleteFolder(folder.id)
        let didPersistFolderDelete = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistFolderDelete)

        context = ModelContext(container)
        XCTAssertNil(try fetchFolder(folder.id, in: context))
        storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertNil(storedPin.folderId)
        XCTAssertTrue(storedPin.isSpacePinned)
    }

    func testIncrementalSpaceMembershipAndOrderPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let spaceA = tabManager.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.createNewTab(url: "https://example.com/a", in: spaceA, activate: true)
        _ = tabManager.createNewTab(url: "https://example.com/a2", in: spaceA, activate: false)
        let spaceB = tabManager.createSpace(name: "B", profileId: profileId)
        let tabB = tabManager.createNewTab(url: "https://example.com/b", in: spaceB, activate: true)

        tabManager.moveTab(tabA.id, to: spaceB.id)
        tabManager.reorderRegularTabs(tabA, in: spaceB.id, to: 0)

        let didPersistMove = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistMove)

        let context = ModelContext(container)
        let storedMovedTab = try XCTUnwrap(fetchTab(tabA.id, in: context))
        let storedExistingTab = try XCTUnwrap(fetchTab(tabB.id, in: context))
        XCTAssertEqual(storedMovedTab.spaceId, spaceB.id)
        XCTAssertEqual(storedMovedTab.index, 0)
        XCTAssertEqual(storedExistingTab.spaceId, spaceB.id)
        XCTAssertEqual(storedExistingTab.index, 1)
    }

    func testSelectionOnlyPersistenceCreatesAndUpdatesState() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Select", profileId: UUID())
        _ = tabManager.createNewTab(url: "https://example.com/one", in: space, activate: true)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)

        let didPersistInitialSelectionState = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistInitialSelectionState)
        tabManager.setActiveTab(second)

        try await waitForPersistedState(in: container) { state in
            state.currentTabID == second.id && state.currentSpaceID == space.id
        }
    }

    func testRuntimeStateBatchFlushUpdatesStoredTabFields() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Runtime", profileId: UUID())
        let tab = tabManager.createNewTab(url: "https://example.com/initial", in: space, activate: true)

        let didPersistInitial = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistInitial)

        tab.url = try XCTUnwrap(URL(string: "https://example.com/runtime"))
        tab.name = "Runtime Updated"
        tab.canGoBack = true
        tab.canGoForward = true

        tabManager.scheduleRuntimeStatePersistence(for: tab)
        let flushedCount = await tabManager.flushRuntimeStatePersistenceAwaitingResult()

        XCTAssertEqual(flushedCount, 1)
        let context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.urlString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.currentURLString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.name, "Runtime Updated")
        XCTAssertTrue(storedTab.canGoBack)
        XCTAssertTrue(storedTab.canGoForward)
    }

    func testFullReconcileDeletesStaleEntitiesAndPreservesFolders() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Clean", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Keep")
        _ = tabManager.createNewTab(url: "https://example.com/keep", in: space, activate: true)
        let didPersistInitial = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistInitial)

        let staleSpaceId = UUID()
        let staleTabId = UUID()
        let staleFolderId = UUID()
        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(id: staleSpaceId, name: "Stale", icon: "xmark", index: 99)
        )
        mutationContext.insert(
            TabEntity(
                id: staleTabId,
                urlString: "https://example.com/stale",
                name: "Stale",
                isPinned: false,
                index: 0,
                spaceId: staleSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: staleFolderId,
                name: "Stale",
                icon: "folder",
                color: "#000000",
                spaceId: staleSpaceId,
                isOpen: false,
                index: 0
            )
        )
        try mutationContext.save()

        let didFullReconcile = await tabManager.persistFullReconcileAwaitingResult(reason: "test full reconcile")
        XCTAssertTrue(didFullReconcile)

        let context = ModelContext(container)
        XCTAssertNil(try fetchSpace(staleSpaceId, in: context))
        XCTAssertNil(try fetchTab(staleTabId, in: context))
        XCTAssertNil(try fetchFolder(staleFolderId, in: context))
        XCTAssertNotNil(try fetchFolder(folder.id, in: context))
    }

    func testRequestedFullReconcileFallbackDeletesStaleEntities() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Fallback", profileId: UUID())
        _ = tabManager.createNewTab(url: "https://example.com/live", in: space, activate: true)
        let didPersistInitial = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistInitial)

        let staleTabId = UUID()
        let mutationContext = ModelContext(container)
        mutationContext.insert(
            TabEntity(
                id: staleTabId,
                urlString: "https://example.com/stale",
                name: "Stale",
                isPinned: false,
                index: 0,
                spaceId: space.id
            )
        )
        try mutationContext.save()

        tabManager.requestFullStructuralReconcile(reason: "test fallback")
        let didFallback = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didFallback)

        let context = ModelContext(container)
        XCTAssertNil(try fetchTab(staleTabId, in: context))
    }

    func testStartupRestorePreservesOrderingSelectionAndDoesNotScheduleStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceAId = UUID()
        let spaceBId = UUID()
        let selectedTabId = UUID()
        let firstTabId = UUID()
        let folderFirstId = UUID()
        let folderSecondId = UUID()
        let pinnedFirstId = UUID()
        let pinnedSecondId = UUID()
        let spacePinnedFirstId = UUID()
        let spacePinnedSecondId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceAId,
                name: "A",
                icon: "square.grid.2x2",
                index: 1,
                profileId: profileId
            )
        )
        mutationContext.insert(
            SpaceEntity(
                id: spaceBId,
                name: "B",
                icon: "person.crop.circle",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderSecondId,
                name: "Later",
                icon: "zen:book",
                color: "#111111",
                spaceId: spaceAId,
                isOpen: false,
                index: 1
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderFirstId,
                name: "First",
                icon: "zen:bookmark",
                color: "#222222",
                spaceId: spaceAId,
                isOpen: true,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedSecondId,
                urlString: "https://example.com/pinned-second",
                name: "Pinned Second",
                isPinned: true,
                index: 1,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedFirstId,
                urlString: "https://example.com/pinned-first",
                name: "Pinned First",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedSecondId,
                urlString: "https://example.com/space-pinned-second",
                name: "Space Pinned Second",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedFirstId,
                urlString: "https://example.com/space-pinned-first",
                name: "Space Pinned First",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: spaceAId,
                folderId: folderFirstId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: selectedTabId,
                urlString: "https://example.com/selected",
                name: "Selected",
                isPinned: false,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: firstTabId,
                urlString: "https://example.com/first",
                name: "First",
                isPinned: false,
                index: 0,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: selectedTabId, currentSpaceID: spaceAId))
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaces.map(\.id), [spaceBId, spaceAId])
        XCTAssertEqual(tabManager.tabsBySpace[spaceAId]?.map(\.id), [firstTabId, selectedTabId])
        XCTAssertEqual(tabManager.foldersBySpace[spaceAId]?.map(\.id), [folderFirstId, folderSecondId])
        XCTAssertEqual(tabManager.pinnedByProfile[profileId]?.map(\.id), [pinnedFirstId, pinnedSecondId])
        XCTAssertEqual(
            tabManager.spacePinnedShortcuts[spaceAId]?.map(\.id),
            [spacePinnedFirstId, spacePinnedSecondId]
        )
        XCTAssertEqual(tabManager.currentSpace?.id, spaceAId)
        XCTAssertEqual(tabManager.currentTab?.id, selectedTabId)
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)
    }

    func testStartupRestoreRepairsMalformedPersistedStateAfterMainApply() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let validSpaceId = UUID()
        let missingSpaceId = UUID()
        let validTabId = UUID()
        let orphanTabId = UUID()
        let orphanFolderId = UUID()
        let missingFolderId = UUID()
        let folderChildPinId = UUID()
        let noSpacePinId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: validSpaceId,
                name: "Valid",
                icon: "square.grid.2x2",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: validTabId,
                urlString: "https://example.com/valid",
                name: "Valid",
                isPinned: false,
                index: 0,
                spaceId: validSpaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: orphanTabId,
                urlString: "https://example.com/orphan",
                name: "Orphan",
                isPinned: false,
                index: 1,
                spaceId: missingSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: orphanFolderId,
                name: "Orphan Folder",
                icon: "zen:book",
                color: "#333333",
                spaceId: missingSpaceId,
                isOpen: false,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: folderChildPinId,
                urlString: "https://example.com/folder-child",
                name: "Folder Child",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: validSpaceId,
                folderId: missingFolderId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: noSpacePinId,
                urlString: "https://example.com/no-space",
                name: "No Space",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: nil
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: UUID(), currentSpaceID: missingSpaceId))
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.currentSpace?.id, validSpaceId)
        XCTAssertEqual(tabManager.currentTab?.id, validTabId)
        XCTAssertEqual(tabManager.tabsBySpace[validSpaceId]?.map(\.id), [validTabId])
        let repairedPin = try XCTUnwrap(tabManager.spacePinnedShortcuts[validSpaceId]?.first)
        XCTAssertEqual(repairedPin.id, folderChildPinId)
        XCTAssertNil(repairedPin.folderId)
        XCTAssertNil(tabManager.spacePinnedShortcuts[missingSpaceId])
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)

        try await waitForStoreRepair(in: container) { context in
            let repairedStoredPin = try fetchTab(folderChildPinId, in: context)
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(orphanTabId, in: context) == nil
                && fetchFolder(orphanFolderId, in: context) == nil
                && fetchTab(noSpacePinId, in: context) == nil
                && repairedStoredPin?.folderId == nil
                && state?.currentSpaceID == validSpaceId
                && state?.currentTabID == validTabId
        }
    }

    func testStartupRestoreCurrentFormatDoesNotPersistOrDuplicateAcrossRepeatedLoads() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)

        await tabManager.persistence.debugResetPersistenceEvents()
        let firstLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(firstLoad)
        try await waitPastStructuralDebounce()

        let firstLoadEvents = await tabManager.persistence.debugPersistenceEventsSnapshot()
        XCTAssertEqual(firstLoadEvents, [])
        XCTAssertEqual(tabManager.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabsBySpace[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        XCTAssertEqual(tabManager.currentSpace?.id, fixture.spaceAId)
        XCTAssertEqual(tabManager.currentTab?.id, fixture.secondTabId)
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)

        await tabManager.persistence.debugResetPersistenceEvents()
        let secondLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(secondLoad)
        try await waitPastStructuralDebounce()

        let secondLoadEvents = await tabManager.persistence.debugPersistenceEventsSnapshot()
        XCTAssertEqual(secondLoadEvents, [])
        XCTAssertEqual(tabManager.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabsBySpace[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)
    }

    func testPostRestoreStructuralMutationPersistsOnceWithoutDuplicatingRestoredGraph() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)

        let didLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(didLoad)
        try await waitPastStructuralDebounce()
        await tabManager.persistence.debugResetPersistenceEvents()

        let restoredSpace = try XCTUnwrap(tabManager.spaces.first { $0.id == fixture.spaceAId })
        let created = tabManager.createNewTab(
            url: "https://example.com/post-restore",
            in: restoredSpace,
            activate: false
        )

        let didPersist = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersist)
        let events = await tabManager.persistence.debugPersistenceEventsSnapshot()

        XCTAssertEqual(events.map(\.kind), [.incremental])
        XCTAssertNotNil(try fetchTab(created.id, in: ModelContext(container)))
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 5)
    }

    func testStructuralTransactionPersistsFinalOrderOnce() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Batch", profileId: UUID())
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)

        let didPersistInitial = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistInitial)
        await tabManager.persistence.debugResetPersistenceEvents()

        tabManager.withStructuralUpdateTransaction {
            tabManager.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.reorderRegularTabs(second, in: space.id, to: 3)
        }

        let didPersistBatch = await tabManager.flushStructuralPersistenceAwaitingResult()
        XCTAssertTrue(didPersistBatch)
        let events = await tabManager.persistence.debugPersistenceEventsSnapshot()

        XCTAssertEqual(events.map(\.kind), [.incremental])
        XCTAssertEqual(try fetchTab(third.id, in: ModelContext(container))?.index, 0)
        XCTAssertEqual(try fetchTab(first.id, in: ModelContext(container))?.index, 1)
        XCTAssertEqual(try fetchTab(second.id, in: ModelContext(container))?.index, 2)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private struct CurrentFormatRestoreFixture {
        let profileId: UUID
        let spaceAId: UUID
        let spaceBId: UUID
        let folderId: UUID
        let firstTabId: UUID
        let secondTabId: UUID
        let pinnedTabId: UUID
        let spacePinnedTabId: UUID
    }

    private func insertCurrentFormatRestoreFixture(
        in container: ModelContainer
    ) throws -> CurrentFormatRestoreFixture {
        let fixture = CurrentFormatRestoreFixture(
            profileId: UUID(),
            spaceAId: UUID(),
            spaceBId: UUID(),
            folderId: UUID(),
            firstTabId: UUID(),
            secondTabId: UUID(),
            pinnedTabId: UUID(),
            spacePinnedTabId: UUID()
        )
        let context = ModelContext(container)
        context.insert(
            SpaceEntity(
                id: fixture.spaceAId,
                name: "A",
                icon: "square.grid.2x2",
                index: 0,
                profileId: fixture.profileId
            )
        )
        context.insert(
            SpaceEntity(
                id: fixture.spaceBId,
                name: "B",
                icon: "person.crop.circle",
                index: 1,
                profileId: fixture.profileId
            )
        )
        context.insert(
            FolderEntity(
                id: fixture.folderId,
                name: "Docs",
                icon: "zen:book",
                color: "#111111",
                spaceId: fixture.spaceAId,
                isOpen: true,
                index: 0
            )
        )
        context.insert(
            TabEntity(
                id: fixture.firstTabId,
                urlString: "https://example.com/one",
                name: "One",
                isPinned: false,
                index: 0,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.secondTabId,
                urlString: "https://example.com/two",
                name: "Two",
                isPinned: false,
                index: 1,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.pinnedTabId,
                urlString: "https://example.com/pinned",
                name: "Pinned",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: fixture.profileId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.spacePinnedTabId,
                urlString: "https://example.com/space-pinned",
                name: "Space Pinned",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: fixture.spaceAId,
                folderId: fixture.folderId
            )
        )
        context.insert(
            TabsStateEntity(
                currentTabID: fixture.secondTabId,
                currentSpaceID: fixture.spaceAId
            )
        )
        try context.save()
        return fixture
    }

    private func fetchTab(_ id: UUID, in context: ModelContext) throws -> TabEntity? {
        let tabId = id
        let predicate = #Predicate<TabEntity> { $0.id == tabId }
        return try context.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
    }

    private func fetchFolder(_ id: UUID, in context: ModelContext) throws -> FolderEntity? {
        let folderId = id
        let predicate = #Predicate<FolderEntity> { $0.id == folderId }
        return try context.fetch(FetchDescriptor<FolderEntity>(predicate: predicate)).first
    }

    private func fetchSpace(_ id: UUID, in context: ModelContext) throws -> SpaceEntity? {
        let spaceId = id
        let predicate = #Predicate<SpaceEntity> { $0.id == spaceId }
        return try context.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate)).first
    }

    private func assertStoreShape(
        in container: ModelContainer,
        spaces expectedSpaces: Int,
        folders expectedFolders: Int,
        tabs expectedTabs: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = ModelContext(container)
        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>())
        let folders = try context.fetch(FetchDescriptor<FolderEntity>())
        let tabs = try context.fetch(FetchDescriptor<TabEntity>())

        XCTAssertEqual(spaces.count, expectedSpaces, file: file, line: line)
        XCTAssertEqual(folders.count, expectedFolders, file: file, line: line)
        XCTAssertEqual(tabs.count, expectedTabs, file: file, line: line)
        XCTAssertEqual(Set(spaces.map(\.id)).count, spaces.count, file: file, line: line)
        XCTAssertEqual(Set(folders.map(\.id)).count, folders.count, file: file, line: line)
        XCTAssertEqual(Set(tabs.map(\.id)).count, tabs.count, file: file, line: line)
    }

    private func waitForPersistedState(
        in container: ModelContainer,
        matching predicate: (TabsStateEntity) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first,
               try predicate(state) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertTrue(try predicate(state))
    }

    private func waitForStoreRepair(
        in container: ModelContainer,
        matching predicate: (ModelContext) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if try predicate(context) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        XCTAssertTrue(try predicate(context))
    }

    private func waitPastStructuralDebounce() async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
    }
}
