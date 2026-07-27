import XCTest

@testable import Sumi

@MainActor
final class WindowSessionRestoreCycleTests: XCTestCase {
    func testSnapshotCanBeClaimedOnlyOnceUntilCycleReset() throws {
        let fixture = try makeFixture()
        let cycle = WindowSessionRestoreCycle()

        let first = try XCTUnwrap(
            cycle.claimSnapshot(
                from: fixture.store,
                for: BrowserWindowState()
            )
        )
        XCTAssertEqual(first.currentSpaceId, fixture.spaceId)
        XCTAssertNil(
            cycle.claimSnapshot(
                from: fixture.store,
                for: BrowserWindowState()
            )
        )

        cycle.reset(store: fixture.store)

        let nextCycle = try XCTUnwrap(
            cycle.claimSnapshot(
                from: fixture.store,
                for: BrowserWindowState()
            )
        )
        XCTAssertEqual(nextCycle.currentSpaceId, fixture.spaceId)
    }

    func testIncognitoWindowDoesNotConsumeGlobalSnapshotClaim() throws {
        let fixture = try makeFixture()
        let cycle = WindowSessionRestoreCycle()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true

        XCTAssertNil(
            cycle.claimSnapshot(
                from: fixture.store,
                for: incognitoWindow
            )
        )
        XCTAssertNotNil(
            cycle.claimSnapshot(
                from: fixture.store,
                for: BrowserWindowState()
            )
        )
    }

    func testMissingSnapshotDoesNotConsumeFutureClaim() throws {
        let database = try SumiDatabase.inMemory()
        let key = "session"
        let store = WindowSessionSnapshotStore(database: database, key: key)
        let cycle = WindowSessionRestoreCycle()

        XCTAssertNil(
            cycle.claimSnapshot(from: store, for: BrowserWindowState())
        )

        let snapshot = makeSnapshot(spaceId: UUID())
        try database.transaction {
            try $0.documents.save(
                try JSONEncoder().encode(snapshot),
                forKey: key
            )
        }
        XCTAssertNotNil(
            cycle.claimSnapshot(from: store, for: BrowserWindowState())
        )
    }

    private func makeFixture() throws -> (
        store: WindowSessionSnapshotStore,
        spaceId: UUID
    ) {
        let database = try SumiDatabase.inMemory()
        let key = "session"
        let spaceId = UUID()
        try database.transaction {
            try $0.documents.save(
                try JSONEncoder().encode(makeSnapshot(spaceId: spaceId)),
                forKey: key
            )
        }
        return (
            WindowSessionSnapshotStore(database: database, key: key),
            spaceId
        )
    }

    private func makeSnapshot(spaceId: UUID) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: spaceId,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: true,
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            commandPaletteDraft: CommandPaletteDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }
}
