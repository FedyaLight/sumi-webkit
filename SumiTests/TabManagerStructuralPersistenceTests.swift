import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralPersistenceTests: XCTestCase {
    func testFullReconcilePreservesMutationsAcceptedDuringWrite() async throws {
        let store = SuspendedStructuralPersistenceStore()
        let state = TabStateStore()
        let database = try SumiDatabase.inMemory()
        let writes = TabStoreWriteExecutor(database: database)
        let persistence = TabStructuralPersistenceService(
            structuralStore: store,
            selectionStore: TabSelectionStore(writes: writes),
            runtimeStateCoalescer: RuntimeStateCoalescer { _ in },
            state: state
        )
        let initialSpace = Space(name: "Initial")
        state.spaces.replaceSpaces([initialSpace])
        persistence.markAllSpacesStructurallyDirty()

        let fullWrite = Task {
            await persistence.persistFullReconcileAwaitingResult(
                reason: "race regression"
            )
        }
        await store.waitUntilFullWriteStarts()

        let laterDeletedSpaceID = UUID()
        persistence.markSpaceStructurallyDeleted(laterDeletedSpaceID)
        let incrementalWrite = Task {
            await persistence.persistPendingStructuralChangesAwaitingResult()
        }

        await store.finishFullWrite()

        let didPersistFull = await fullWrite.value
        let didPersistIncremental = await incrementalWrite.value
        let incrementalWriteCount = await store.incrementalWriteCount
        XCTAssertTrue(didPersistFull)
        XCTAssertTrue(didPersistIncremental)
        XCTAssertEqual(incrementalWriteCount, 1)
        XCTAssertTrue(persistence.dirtySet.isEmpty)
    }

    func testFullReconcilePersistsAndReloadsBrowserStructure() async throws {
        let database = try SumiDatabase.inMemory()
        let browser = makeBrowser(database: database)
        let profile = try browser.profileManager.createProfile(name: "Work")
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Research",
                icon: "circle",
                profileID: profile.id
            )
        )
        let first = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let second = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )

        let didPersist = await browser.structuralPersistence
            .persistFullReconcileAwaitingResult(reason: "test")
        XCTAssertTrue(didPersist)

        let stored = try database.read { connection in
            (
                try connection.workspace.spaces(),
                try connection.workspace.tabs(),
                try connection.workspace.state()
            )
        }
        XCTAssertEqual(stored.0.map(\.id), [space.id])
        XCTAssertEqual(stored.1.map(\.id), [first.id, second.id])
        XCTAssertEqual(stored.2?.currentTabID, first.id)
        XCTAssertEqual(stored.2?.currentSpaceID, space.id)

        let payload = try await TabRestoreLoader(database: database).load(
            defaultProfileId: profile.id
        )
        XCTAssertEqual(payload.spaces.map(\.id), [space.id])
        XCTAssertEqual(
            payload.regularTabsBySpace[space.id]?.map(\.id),
            [first.id, second.id]
        )
    }

    func testIncrementalRemovalDeletesThePersistedTab() async throws {
        let database = try SumiDatabase.inMemory()
        let browser = makeBrowser(database: database)
        let profile = try browser.profileManager.createProfile(name: "Work")
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Research",
                icon: "circle",
                profileID: profile.id
            )
        )
        let survivor = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://keep.example",
            in: space,
            activate: true
        )
        let removed = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://remove.example",
            in: space,
            activate: false
        )
        let didSeed = await browser.structuralPersistence
            .persistFullReconcileAwaitingResult(reason: "seed")
        XCTAssertTrue(didSeed)

        browser.tabClosureService.removeTab(removed.id)
        let didPersistRemoval = await browser.structuralPersistence
            .persistFullReconcileAwaitingResult(reason: "verify removal")
        XCTAssertTrue(didPersistRemoval)

        let storedIDs = try database.read {
            try $0.workspace.tabs().map(\.id)
        }
        XCTAssertEqual(storedIDs, [survivor.id])
    }

    func testExtensionOwnedRegularTabIsNeverPersisted() async throws {
        let database = try SumiDatabase.inMemory()
        let browser = makeBrowser(database: database)
        let profile = try browser.profileManager.createProfile(name: "Work")
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Research",
                icon: "circle",
                profileID: profile.id
            )
        )
        let normal = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: space,
            activate: true
        )
        _ = browser.regularTabLifecycleOwner.createNewTab(
            url: "webkit-extension://extension/page.html",
            in: space,
            activate: false
        )

        let didPersist = await browser.structuralPersistence
            .persistFullReconcileAwaitingResult(reason: "test")
        XCTAssertTrue(didPersist)

        let storedIDs = try database.read {
            try $0.workspace.tabs().map(\.id)
        }
        XCTAssertEqual(storedIDs, [normal.id])
    }

    private func makeBrowser(database: SumiDatabase) -> BrowserManager {
        BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                database: database
            ),
            automaticallyStartPersistedStateLoad: false
        )
    }
}

private actor SuspendedStructuralPersistenceStore:
    TabStructuralSnapshotPersisting {
    private var fullWriteStarted = false
    private var fullWriteStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var fullWriteContinuation: CheckedContinuation<Bool, Never>?
    private(set) var incrementalWriteCount = 0

    func persistFullReconcile(
        snapshot: TabPersistenceSnapshot,
        generation: Int
    ) async -> Bool {
        _ = snapshot
        _ = generation
        fullWriteStarted = true
        fullWriteStartWaiters.forEach { $0.resume() }
        fullWriteStartWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            fullWriteContinuation = continuation
        }
    }

    func persistIncremental(
        delta: TabStructuralPersistenceDelta,
        generation: Int
    ) async -> Bool {
        _ = delta
        _ = generation
        incrementalWriteCount += 1
        return true
    }

    func waitUntilFullWriteStarts() async {
        guard fullWriteStarted == false else { return }
        await withCheckedContinuation { continuation in
            fullWriteStartWaiters.append(continuation)
        }
    }

    func finishFullWrite() {
        fullWriteContinuation?.resume(returning: true)
        fullWriteContinuation = nil
    }
}
