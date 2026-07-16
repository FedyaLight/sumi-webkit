import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerDeinitializationTests: XCTestCase {
    func testDeinitDetachesExternallyRetainedRuntimeConnection() throws {
        var tabManager: TabManager? = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        var sentinel: RuntimeLifetimeSentinel? = RuntimeLifetimeSentinel()
        weak var releasedSentinel = sentinel
        attachRuntime(
            retaining: try XCTUnwrap(sentinel),
            to: try XCTUnwrap(tabManager)
        )
        let connection = try XCTUnwrap(tabManager?.runtimePortConnection)
        weak var released = tabManager
        sentinel = nil

        XCTAssertNotNil(releasedSentinel)

        tabManager = nil

        XCTAssertNil(released)
        XCTAssertNil(releasedSentinel)
        XCTAssertNil(connection.current)
    }

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

    func testShortcutFolderCompositionMaterializesWithoutDependencyCycle()
        throws {
        let container = try makeContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )

        let folderMutations = tabManager.folderMutationOwner
        let pinStore = tabManager.shortcutPinStoreOwner
        let pinCommands = tabManager.shortcutPinCommandOwner
        let regularConversion = tabManager.regularTabShortcutConversion

        XCTAssertIdentical(tabManager.folderMutationOwner, folderMutations)
        XCTAssertIdentical(tabManager.shortcutPinStoreOwner, pinStore)
        XCTAssertIdentical(tabManager.shortcutPinCommandOwner, pinCommands)
        XCTAssertIdentical(
            tabManager.regularTabShortcutConversion,
            regularConversion
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func attachRuntime(
        retaining sentinel: RuntimeLifetimeSentinel,
        to tabManager: TabManager
    ) {
        let runtime = TestRuntimePorts.make(
            profileExists: { [sentinel] _ in
                _ = sentinel
                return true
            }
        )
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
    }
}

private final class RuntimeLifetimeSentinel {}
