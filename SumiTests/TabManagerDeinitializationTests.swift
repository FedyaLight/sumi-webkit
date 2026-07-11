import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerDeinitializationTests: XCTestCase {
    func testDeinitWithUnusedStructuralGraphReleasesWithoutTrap() throws {
        let container = try makeContainer()
        var tabManager: TabManager? = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        weak var released = tabManager

        tabManager = nil

        XCTAssertNil(released)
    }

    func testDeinitReleasesMaterializedStructuralLookup() throws {
        let container = try makeContainer()
        var tabManager: TabManager? = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        tabManager?.structuralLookupCoordinator.rebuild()
        weak let releasedLookup = tabManager?.structuralLookupCoordinator
        weak let released = tabManager

        tabManager = nil

        XCTAssertNil(released)
        XCTAssertNil(releasedLookup)
    }

    func testDeinitReleasesMaterializedSpaceServices() throws {
        let container = try makeContainer()
        var tabManager: TabManager? = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        weak let releasedActivation = tabManager?.spaceServices.activation
        weak let releasedCatalog = tabManager?.spaceServices.catalog
        weak let releasedManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedManager)
        XCTAssertNil(releasedActivation)
        XCTAssertNil(releasedCatalog)
    }

    func testDeinitReleasesMaterializedShortcutRuntimeGraph() throws {
        let container = try makeContainer()
        var tabManager: TabManager? = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        weak let releasedRegistry = tabManager?.liveShortcutTabs
        weak let releasedWindowQuery = tabManager?.shortcutTabWindowQuery
        weak let releasedBindings = tabManager?.shortcutTabBindings
        weak let releasedMaterializer = tabManager?.shortcutTabMaterializer
        weak let releasedRegularConversion = tabManager?
            .regularTabShortcutConversion
        weak let releasedPinPromotion = tabManager?.shortcutPinToRegularTab
        weak let releasedRetirement = tabManager?.shortcutLiveTabRetirement
        weak let releasedPromotion = tabManager?.shortcutTabPromotion
        weak let releasedManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedManager)
        XCTAssertNil(releasedRegistry)
        XCTAssertNil(releasedWindowQuery)
        XCTAssertNil(releasedBindings)
        XCTAssertNil(releasedMaterializer)
        XCTAssertNil(releasedRegularConversion)
        XCTAssertNil(releasedPinPromotion)
        XCTAssertNil(releasedRetirement)
        XCTAssertNil(releasedPromotion)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
