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

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
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
}
