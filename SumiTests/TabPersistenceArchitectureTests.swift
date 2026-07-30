import XCTest

@testable import Sumi

@MainActor
final class TabPersistenceArchitectureTests: XCTestCase {
    func testStructuralStoreRejectsStaleGenerationWithoutOverwritingNewerSnapshot() async throws {
        let container = try makeContainer()
        let writes = TabStoreWriteExecutor(database: container)
        let store = TabStructuralSnapshotStore(writes: writes)
        let spaceId = UUID()
        let profileId = UUID()
        try container.transaction {
            try $0.profiles.save(
                ProfileRecord(id: profileId, name: "Profile", index: 0)
            )
        }

        let didPersistNewer = await store.persistFullReconcile(
            snapshot: snapshot(spaceId: spaceId, profileId: profileId, name: "newer"),
            generation: 2
        )
        let didPersistStale = await store.persistFullReconcile(
            snapshot: snapshot(spaceId: spaceId, profileId: profileId, name: "stale"),
            generation: 1
        )
        XCTAssertTrue(didPersistNewer)
        XCTAssertFalse(didPersistStale)

        let spaces = try container.read { try $0.workspace.spaces() }
        XCTAssertEqual(spaces.count, 1)
        XCTAssertEqual(spaces.first?.name, "newer")
    }

    func testSelectionAndRuntimeStateShareSerializedWritesWithoutChangingStructure() async throws {
        let container = try makeContainer()
        let writes = TabStoreWriteExecutor(database: container)
        let structural = TabStructuralSnapshotStore(writes: writes)
        let selection = TabSelectionStore(writes: writes)
        let runtime = TabRuntimeStateStore(writes: writes)
        let spaceId = UUID()
        let tabId = UUID()
        let profileId = UUID()
        try container.transaction {
            try $0.profiles.save(
                ProfileRecord(id: profileId, name: "Profile", index: 0)
            )
        }

        let initial = snapshot(
            spaceId: spaceId,
            profileId: profileId,
            name: "Space",
            tabId: tabId
        )
        let didPersist = await structural.persistFullReconcile(snapshot: initial, generation: 1)
        XCTAssertTrue(didPersist)

        async let selectionWrite: Void = selection.persist(
            currentTabID: tabId,
            currentSpaceID: spaceId
        )
        async let runtimeWrite: Void = runtime.persist(
            [
                TabRuntimeStateUpdate(
                    id: tabId,
                    urlString: "https://example.com/updated",
                    currentURLString: "https://example.com/updated",
                    name: "Updated",
                    canGoBack: true,
                    canGoForward: false
                ),
            ]
        )
        _ = await (selectionWrite, runtimeWrite)

        let stored = try container.read { connection in
            (
                try connection.workspace.tabs(),
                try connection.workspace.state(),
                try connection.workspace.spaces()
            )
        }
        let tabs = stored.0
        let state = stored.1
        XCTAssertEqual(stored.2.count, 1)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.name, "Updated")
        XCTAssertEqual(tabs.first?.currentURLString, "https://example.com/updated")
        XCTAssertEqual(state?.currentTabID, tabId)
        XCTAssertEqual(state?.currentSpaceID, spaceId)
    }

    func testRestorePlannerRepairsCorruptRecordsAndBuildsMatchingSnapshot() throws {
        let profileId = UUID()
        let spaceId = UUID()
        let secondSpaceId = UUID()
        let regularTabId = UUID()
        let extensionTabId = UUID()
        let folderId = UUID()
        let records = TabRestoreStoreRecords(
            spaces: [
                TabRestoreSpaceRecord(
                    id: secondSpaceId,
                    name: "Second",
                    icon: "2.circle",
                    index: 1,
                    workspaceThemeData: nil,
                    profileId: profileId
                ),
                TabRestoreSpaceRecord(
                    id: spaceId,
                    name: "First",
                    icon: "1.circle",
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: nil
                ),
            ],
            tabs: [
                regularRecord(id: regularTabId, spaceId: spaceId, index: 2),
                regularRecord(
                    id: extensionTabId,
                    spaceId: spaceId,
                    index: 1,
                    url: "webkit-extension://extension/page.html"
                ),
            ],
            folders: [
                TabRestoreFolderRecord(
                    id: folderId,
                    name: "Folder",
                    icon: "folder",
                    color: "#fff",
                    spaceId: spaceId,
                    parentFolderId: UUID(),
                    isOpen: true,
                    isLiveFolder: true,
                    index: 0
                ),
            ],
            states: [
                TabRestoreStateRecord(
                    currentTabID: extensionTabId,
                    currentSpaceID: spaceId,
                    splitGroupsData: Data("not-json".utf8)
                ),
                TabRestoreStateRecord(
                    currentTabID: nil,
                    currentSpaceID: nil,
                    splitGroupsData: nil
                ),
            ]
        )

        let payload = TabRestorePlanner().makePayload(
            from: records,
            defaultProfileId: profileId
        )

        XCTAssertEqual(payload.spaces.map(\.id), [spaceId, secondSpaceId])
        XCTAssertEqual(payload.regularTabsBySpace[spaceId]?.map(\.id), [regularTabId])
        XCTAssertEqual(payload.currentTabId, regularTabId)
        XCTAssertEqual(payload.currentSpaceId, spaceId)
        XCTAssertNil(payload.foldersBySpace[spaceId]?.first?.parentFolderId)
        XCTAssertEqual(payload.foldersBySpace[spaceId]?.first?.isLiveFolder, true)
        XCTAssertEqual(payload.snapshot.tabs.map(\.id), [regularTabId])
        XCTAssertEqual(payload.snapshot.spaces.map(\.id), [spaceId, secondSpaceId])
        XCTAssertEqual(payload.snapshot.state.currentTabID, regularTabId)
        XCTAssertTrue(payload.repairReasons.contains("removed extension-owned restored tab"))
        XCTAssertTrue(payload.repairReasons.contains("moved folder out of invalid parent"))
        XCTAssertTrue(payload.repairReasons.contains("removed unreadable split groups"))
        XCTAssertTrue(payload.repairReasons.contains("removed duplicate tab state"))
        XCTAssertTrue(payload.repairReasons.contains("assigned default profile to space"))
    }

    private func makeContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    private func snapshot(
        spaceId: UUID,
        profileId: UUID,
        name: String,
        tabId: UUID? = nil
    ) -> TabPersistenceSnapshot {
        TabPersistenceSnapshot(
            spaces: [
                TabPersistenceSpace(
                    id: spaceId,
                    name: name,
                    icon: "circle",
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: profileId
                ),
            ],
            tabs: tabId.map { id in
                [
                    TabPersistenceTab(
                        id: id,
                        urlString: "https://example.com",
                        name: "Initial",
                        index: 0,
                        spaceId: spaceId,
                        isPinned: false,
                        isSpacePinned: false,
                        profileId: profileId,
                        executionProfileId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        currentURLString: "https://example.com",
                        canGoBack: false,
                        canGoForward: false
                    ),
                ]
            } ?? [],
            folders: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: spaceId)
        )
    }

    private func regularRecord(
        id: UUID,
        spaceId: UUID,
        index: Int,
        url: String = "https://example.com"
    ) -> TabRestoreTabRecord {
        TabRestoreTabRecord(
            id: id,
            urlString: url,
            name: "Tab",
            isPinned: false,
            isSpacePinned: false,
            index: index,
            spaceId: spaceId,
            profileId: nil,
            executionProfileId: nil,
            folderId: nil,
            iconAsset: nil,
            currentURLString: url,
            canGoBack: false,
            canGoForward: false
        )
    }
}
