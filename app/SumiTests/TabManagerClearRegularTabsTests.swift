import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerClearRegularTabsTests: XCTestCase {
    func testClearRegularTabs_secondClearRemovesLastActiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "S", profileId: profileId)

        _ = tabManager.createNewTab(in: space, activate: true)
        _ = tabManager.createNewTab(in: space, activate: false)

        XCTAssertEqual(tabManager.tabs(in: space).count, 2)

        tabManager.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.tabs(in: space).count, 1)

        tabManager.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.tabs(in: space).count, 0)
    }

    func testClearRegularTabs_otherSpaceClearsOnlyTargetSpaceTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let spaceA = tabManager.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.createNewTab(in: spaceA, activate: true)
        let spaceB = tabManager.createSpace(name: "B", profileId: profileId)
        _ = tabManager.createNewTab(in: spaceB, activate: true)

        tabManager.setActiveSpace(spaceA, preferredTab: tabA)
        XCTAssertEqual(tabManager.currentTab?.id, tabA.id)

        tabManager.clearRegularTabs(for: spaceB.id)

        XCTAssertTrue(tabManager.tabs(in: spaceB).isEmpty)
        XCTAssertEqual(tabManager.currentTab?.id, tabA.id)
        XCTAssertEqual(tabManager.tabs(in: spaceA).count, 1)
    }

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }
}
