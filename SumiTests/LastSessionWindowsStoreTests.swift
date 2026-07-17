import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowsStoreTests: XCTestCase {
    private struct StoredArchive: Codable {
        let snapshots: [LastSessionWindowSnapshot]
        let tabSnapshot: TabPersistenceSnapshot?
    }

    func testStorePersistsSnapshotsToUserDefaults() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = LastSessionWindowsStore(userDefaults: defaults)
        let snapshot = makeWindowSnapshot()

        store.updateSnapshots([snapshot])

        let reloaded = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.snapshots, [snapshot])
        XCTAssertNil(reloaded.tabSnapshot)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStorePersistsStartupArchiveWithTabSnapshot() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = LastSessionWindowsStore(userDefaults: defaults)
        let windowSnapshot = makeWindowSnapshot()
        let tabSnapshot = makeTabSnapshot()

        store.updateSnapshots([windowSnapshot], tabSnapshot: tabSnapshot)

        let reloaded = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.snapshots, [windowSnapshot])
        XCTAssertEqual(reloaded.tabSnapshot?.spaces.map(\.id), tabSnapshot.spaces.map(\.id))
        XCTAssertEqual(reloaded.tabSnapshot?.tabs.map(\.id), tabSnapshot.tabs.map(\.id))
        XCTAssertEqual(reloaded.tabSnapshot?.state.currentSpaceID, tabSnapshot.state.currentSpaceID)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStoreKeepsDistinctWindowIdentitiesWithIdenticalSessions() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LastSessionWindowsStore(userDefaults: defaults)
        let sharedSession = makeSession()
        let first = LastSessionWindowSnapshot(id: UUID(), session: sharedSession)
        let second = LastSessionWindowSnapshot(id: UUID(), session: sharedSession)

        store.updateSnapshots([first, second, first])

        XCTAssertEqual(store.snapshots, [first, second])
        XCTAssertEqual(
            LastSessionWindowsStore(userDefaults: defaults).snapshots,
            [first, second]
        )
    }

    func testWindowSessionIdentityCanonicalizesMapShapedSelectionOrder() throws {
        let firstSpaceID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondSpaceID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let firstTabID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")
        )
        let secondTabID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-0000-0000-000000000002")
        )
        let firstPinID = try XCTUnwrap(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        )
        let secondPinID = try XCTUnwrap(
            UUID(uuidString: "20000000-0000-0000-0000-000000000002")
        )
        let tabSelections = [
            SpaceTabSelectionSnapshot(spaceId: firstSpaceID, tabId: firstTabID),
            SpaceTabSelectionSnapshot(spaceId: secondSpaceID, tabId: secondTabID),
        ]
        let shortcutSelections = [
            SpaceShortcutSelectionSnapshot(
                spaceId: firstSpaceID,
                shortcutPinId: firstPinID
            ),
            SpaceShortcutSelectionSnapshot(
                spaceId: secondSpaceID,
                shortcutPinId: secondPinID
            ),
        ]

        let forward = makeSession(
            currentSpaceID: firstSpaceID,
            activeTabsBySpace: tabSelections,
            activeShortcutsBySpace: shortcutSelections
        )
        let reversed = makeSession(
            currentSpaceID: firstSpaceID,
            activeTabsBySpace: Array(tabSelections.reversed()),
            activeShortcutsBySpace: Array(shortcutSelections.reversed())
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(Set([forward, reversed]).count, 1)
    }

    func testDecoderCanonicalizesLegacySelectionArrayOrder() throws {
        let firstSpaceID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondSpaceID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let canonical = makeSession(
            currentSpaceID: firstSpaceID,
            activeTabsBySpace: [
                SpaceTabSelectionSnapshot(spaceId: firstSpaceID, tabId: UUID()),
                SpaceTabSelectionSnapshot(spaceId: secondSpaceID, tabId: UUID()),
            ],
            activeShortcutsBySpace: [
                SpaceShortcutSelectionSnapshot(
                    spaceId: firstSpaceID,
                    shortcutPinId: UUID()
                ),
                SpaceShortcutSelectionSnapshot(
                    spaceId: secondSpaceID,
                    shortcutPinId: UUID()
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(canonical)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["activeTabsBySpace"] = Array(
            try XCTUnwrap(
                object["activeTabsBySpace"] as? [[String: Any]]
            ).reversed()
        )
        object["activeShortcutsBySpace"] = Array(
            try XCTUnwrap(
                object["activeShortcutsBySpace"] as? [[String: Any]]
            ).reversed()
        )

        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded, canonical)
    }

    func testDecoderCollapsesDuplicateMapKeysBeforeSnapshotApplication() throws {
        let spaceID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let lowerTabID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")
        )
        let higherTabID = try XCTUnwrap(
            UUID(uuidString: "90000000-0000-0000-0000-000000000001")
        )
        let lowerPinID = try XCTUnwrap(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        )
        let higherPinID = try XCTUnwrap(
            UUID(uuidString: "80000000-0000-0000-0000-000000000001")
        )
        let base = makeSession(currentSpaceID: spaceID)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(base)
            ) as? [String: Any]
        )
        object["activeTabsBySpace"] = try jsonObjects([
            SpaceTabSelectionSnapshot(spaceId: spaceID, tabId: higherTabID),
            SpaceTabSelectionSnapshot(spaceId: spaceID, tabId: lowerTabID),
        ])
        object["activeShortcutsBySpace"] = try jsonObjects([
            SpaceShortcutSelectionSnapshot(
                spaceId: spaceID,
                shortcutPinId: higherPinID
            ),
            SpaceShortcutSelectionSnapshot(
                spaceId: spaceID,
                shortcutPinId: lowerPinID
            ),
        ])

        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.activeTabsBySpace.map(\.tabId), [lowerTabID])
        XCTAssertEqual(
            decoded.activeShortcutsBySpace.map(\.shortcutPinId),
            [lowerPinID]
        )
        XCTAssertNoThrow(
            Dictionary(uniqueKeysWithValues: decoded.activeTabsBySpace.map {
                ($0.spaceId, $0.tabId)
            })
        )
    }

    func testLoadCollapsesDuplicateArchivedWindowIdentities() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sharedID = UUID()
        let first = LastSessionWindowSnapshot(id: sharedID, session: makeSession())
        let duplicate = LastSessionWindowSnapshot(
            id: sharedID,
            session: makeSession()
        )
        let archive = StoredArchive(
            snapshots: [first, duplicate],
            tabSnapshot: nil
        )
        defaults.set(
            try JSONEncoder().encode(archive),
            forKey: "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastSessionWindows"
        )

        let store = LastSessionWindowsStore(userDefaults: defaults)

        XCTAssertEqual(store.snapshots, [first])
    }

    func testCorruptArchiveBlocksProfileMigrationWithoutOverwritingPayload()
        throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastSessionWindows"
        let corruptPayload = Data("not-an-archive".utf8)
        defaults.set(corruptPayload, forKey: key)
        let store = LastSessionWindowsStore(userDefaults: defaults)

        XCTAssertEqual(store.archiveLoadState, .failed)
        XCTAssertFalse(
            store.migrateProfileReferences(
                from: UUID(),
                to: UUID()
            )
        )
        XCTAssertTrue(store.containsProfileReference(to: UUID()))
        XCTAssertEqual(defaults.data(forKey: key), corruptPayload)
        XCTAssertEqual(store.archiveLoadState, .failed)
    }

    private func makeWindowSnapshot() -> LastSessionWindowSnapshot {
        LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSession()
        )
    }

    private func makeSession(
        currentSpaceID: UUID = UUID(),
        activeTabsBySpace: [SpaceTabSelectionSnapshot] = [],
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot] = []
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: currentSpaceID,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: nil,
            activeTabsBySpace: activeTabsBySpace,
            activeShortcutsBySpace: activeShortcutsBySpace,
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }

    private func makeTabSnapshot() -> TabPersistenceSnapshot {
        let spaceId = UUID()
        let tabId = UUID()
        return TabPersistenceSnapshot(
            spaces: [
                TabPersistenceSpace(
                    id: spaceId,
                    name: "Restored",
                    icon: "globe",
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: nil
                ),
            ],
            tabs: [
                TabPersistenceTab(
                    id: tabId,
                    urlString: "https://example.com",
                    name: "Example",
                    index: 0,
                    spaceId: spaceId,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    executionProfileId: nil,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: "https://example.com",
                    canGoBack: false,
                    canGoForward: false
                ),
            ],
            folders: [],
            splitGroups: [],
            state: TabPersistenceSelection(
                currentTabID: tabId,
                currentSpaceID: spaceId
            )
        )
    }

    private func jsonObjects<Value: Encodable>(
        _ values: [Value]
    ) throws -> [[String: Any]] {
        try values.map { value in
            try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(value)
                ) as? [String: Any]
            )
        }
    }
}
