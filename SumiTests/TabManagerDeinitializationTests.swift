import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class TabManagerDeinitializationTests: XCTestCase {
    func testConstructionShellDeinitDoesNotClearExternallyOwnedSessionState() throws {
        let container = try makeContainer()
        var tabManager: TabManager? = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            loadPersistedState: false
        )
        let stateStore = try XCTUnwrap(tabManager?.stateStore)
        let space = Space(name: "Retained session")
        stateStore.spaces.replaceSpaces([space])

        weak var released = tabManager
        tabManager = nil

        XCTAssertNil(released)
        XCTAssertIdentical(stateStore.spaces.spaces.first, space)
    }

    func testRuntimeLifecycleShutdownDetachesAndClearsSessionStateOnce() throws {
        let runtime = BrowserManager()
        let space = Space(name: "Runtime-owned state")
        let tab = runtime.tabFactory.makeTab(spaceId: space.id)
        runtime.spaceStateOwner.replaceSpaces([space])
        runtime.spaceStateOwner.replaceCurrentSpace(space)
        runtime.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        runtime.tabStateStore.selection.replaceCurrentTab(tab)
        XCTAssertNotNil(runtime.runtimePortConnection.current)

        runtime.tabRuntimeLifecycle.shutdown()
        runtime.tabRuntimeLifecycle.shutdown()

        XCTAssertNil(runtime.runtimePortConnection.current)
        assertEmptyState(runtime.tabStateStore)
    }

    func testBrowserManagerDeinitTerminatesRuntimeAndClearsSessionState() throws {
        var browserManager: BrowserManager? = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeContainer()
            )
        )
        let connection = try XCTUnwrap(browserManager?.runtimePortConnection)
        let stateStore = try XCTUnwrap(browserManager?.tabStateStore)
        let space = Space(name: "Browser-owned state")
        stateStore.spaces.replaceSpaces([space])
        weak var released = browserManager

        XCTAssertNotNil(connection.current)

        browserManager = nil

        XCTAssertNil(released)
        XCTAssertNil(connection.current)
        assertEmptyState(stateStore)
    }

    private func assertEmptyState(
        _ stateStore: TabStateStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(stateStore.spaces.spaces.isEmpty, file: file, line: line)
        XCTAssertNil(stateStore.spaces.currentSpace, file: file, line: line)
        XCTAssertTrue(stateStore.regularTabs.allTabs().isEmpty, file: file, line: line)
        XCTAssertTrue(stateStore.splitGroups.groups.isEmpty, file: file, line: line)
        XCTAssertTrue(stateStore.folders.allFolders().isEmpty, file: file, line: line)
        XCTAssertTrue(
            stateStore.shortcutPins.pinnedByProfileSnapshot().isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            stateStore.shortcutPins.spacePinnedShortcutsSnapshot().isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            stateStore.shortcutPins.pendingPinnedWithoutProfileSnapshot().isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            stateStore.transientTabs.allTransientTabs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertNil(stateStore.selection.currentTab, file: file, line: line)
    }

    private func makeContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}
