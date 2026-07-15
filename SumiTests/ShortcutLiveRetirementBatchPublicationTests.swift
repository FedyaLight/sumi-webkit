import Combine
import Observation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveRetirementBatchPublicationTests: XCTestCase {
    func testFixtureWindowQueriesShareExactIdentity() throws {
        let fixture = try PublicationFixture(pinCount: 2)
        let runtime = fixture.tabManager.requireRuntimePorts()
        var enumerated: [BrowserWindowState] = []

        runtime.forEachWindowState { enumerated.append($0) }

        XCTAssertIdentical(runtime.windowState(for: fixture.window.id), fixture.window)
        XCTAssertEqual(enumerated.count, 1)
        XCTAssertIdentical(enumerated.first, fixture.window)
    }

    func testDeletedPinFirstCallbackSeesTerminalCatalogTopologyAndModel()
        throws {
        let fixture = try PublicationFixture(pinCount: 3)
        let removedPin = fixture.pins[0]
        let removedTab = fixture.liveTabs[0]
        let remaining = try XCTUnwrap(
            fixture.group.removingMember(.shortcutPin(removedPin.id))
        )
        let oracle = PublicationOracle()
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                oracle.structuralCallbacks += 1
                oracle.assertTerminal(
                    fixture: fixture,
                    removedPin: removedPin,
                    removedTab: removedTab,
                    remaining: remaining
                )
                let repeated = fixture.tabManager.shortcutLiveTabRetirement
                    .retire(pinId: removedPin.id, in: fixture.window.id)
                XCTAssertFalse(repeated.didRetire)
            }
        withObservationTracking {
            _ = fixture.window.currentTabId
            _ = fixture.window.currentShortcutPinId
            _ = fixture.window.splitSelection
        } onChange: {
            MainActor.assumeIsolated {
                oracle.windowCallbacks += 1
                oracle.assertTerminal(
                    fixture: fixture,
                    removedPin: removedPin,
                    removedTab: removedTab,
                    remaining: remaining
                )
            }
        }

        fixture.tabManager.shortcutPinCommandOwner
            .removeShortcutPin(removedPin)

        XCTAssertEqual(oracle.windowCallbacks, 1)
        XCTAssertEqual(oracle.structuralCallbacks, 1)
        XCTAssertEqual(oracle.failures, 0)
        _ = cancellable
    }

    func testLifecycleReentrySameIDReplacementSurvivesAndFinishIsIdempotent()
        throws {
        let window = BrowserWindowState()
        var events: [String] = []
        var replacement: Tab?
        var tabManager: TabManager!
        tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            notifyTabClosedIfLoaded: { tab in
                XCTAssertIdentical(
                    tabManager.tabCollectionMembershipOwner.tab(for: tab.id),
                    replacement
                )
                events.append("extension")
            },
            persistWindowSession: { _ in events.append("persist") }
        )
        window.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
            PublicationFixture.makePin(index: 0, spaceID: space.id), at: 0
        ))
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                pin, in: window.id, currentSpaceId: space.id
            )
        )
        window.currentSpaceId = space.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = pin.id
        window.currentShortcutPinRole = pin.role
        let structure = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in events.append("structure") }
        let lifecycle = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: liveTab,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                events.append("lifecycle")
                let current = Tab(
                    id: liveTab.id,
                    url: URL(string: "https://replacement.example")!,
                    name: "Replacement",
                    spaceId: space.id,
                    loadsCachedFaviconOnInit: false
                )
                replacement = current
                tabManager.tabCollectionMembershipOwner.attach(current)
            }
        }

        let prepared = try XCTUnwrap(
            tabManager.shortcutLiveTabRetirement.prepareRetirement(
                pinId: pin.id, in: window.id
            )
        )
        _ = tabManager.shortcutLiveTabRetirement.finish(prepared)
        _ = tabManager.shortcutLiveTabRetirement.finish(prepared)

        XCTAssertEqual(events, ["structure", "lifecycle", "extension", "persist"])
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id),
            replacement
        )
        NotificationCenter.default.removeObserver(lifecycle)
        _ = structure
    }

    func testDeletedFolderFirstWindowCallbackSeesFolderAndPinsGone()
        throws {
        let fixture = try PublicationFixture(pinCount: 3, foldered: true)
        let folder = try XCTUnwrap(fixture.folder)
        let removedPin = fixture.pins[0]
        let removedTab = fixture.liveTabs[0]
        let oracle = PublicationOracle()
        withObservationTracking {
            _ = fixture.window.currentTabId
            _ = fixture.window.currentShortcutPinId
            _ = fixture.window.splitSelection
        } onChange: {
            MainActor.assumeIsolated {
                oracle.windowCallbacks += 1
                XCTAssertNil(
                    fixture.tabManager.folderCollectionStateOwner.folder(
                        by: folder.id
                    )
                )
                XCTAssertTrue(fixture.pins.allSatisfy {
                    fixture.tabManager.shortcutPinCollectionStateOwner
                        .shortcutPin(by: $0.id) == nil
                })
                XCTAssertTrue(fixture.liveTabs.allSatisfy {
                    fixture.tabManager.liveShortcutTabs.entry(tabId: $0.id)
                        == nil
                        && fixture.tabManager.tabCollectionMembershipOwner
                            .tab(for: $0.id) == nil
                })
                XCTAssertNil(fixture.tabManager.splitGroupStore.group(
                    id: fixture.group.id
                ))
                XCTAssertNil(fixture.window.splitSelection)
                XCTAssertNotEqual(
                    fixture.window.currentShortcutPinId,
                    removedPin.id
                )
                XCTAssertNil(fixture.tabManager.liveShortcutTabs.entry(
                    tabId: removedTab.id
                ))
            }
        }

        fixture.tabManager.folderMutationOwner.deleteFolder(folder.id)

        XCTAssertEqual(oracle.windowCallbacks, 1)
    }

    func testHostedSplitFirstWindowCallbackSeesTerminalEmptyPresentation()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        var handoffCount = 0
        var compositorRefreshCount = 0
        let service = ShortcutHostedSplitUnloadService(
            runtimeLease: { [weak tabManager = fixture.tabManager] in
                guard let tabManager else { return nil }
                return SplitShortcutRuntimeLease(tabManager: tabManager)
            },
            performImmediateVisualHandoff: { _ in handoffCount += 1 },
            refreshCompositor: { _ in compositorRefreshCount += 1 }
        )
        let oracle = PublicationOracle()
        withObservationTracking {
            _ = fixture.window.currentTabId
            _ = fixture.window.currentShortcutPinId
            _ = fixture.window.splitSelection
            _ = fixture.window.isShowingEmptyState
        } onChange: {
            MainActor.assumeIsolated {
                oracle.windowCallbacks += 1
                let isTerminal = fixture.window.currentTabId == nil
                    && fixture.window.currentShortcutPinId == nil
                    && fixture.window.splitSelection == nil
                    && fixture.window.isShowingEmptyState
                    && fixture.liveTabs.allSatisfy { tab in
                        fixture.tabManager.liveShortcutTabs.entry(
                            tabId: tab.id
                        ) == nil
                            && fixture.tabManager.tabCollectionMembershipOwner
                                .tab(for: tab.id) == nil
                    }
                    && fixture.tabManager.splitGroupStore.group(
                        id: fixture.group.id
                    ) == fixture.group
                if isTerminal == false { oracle.failures += 1 }
                XCTAssertTrue(isTerminal)
                XCTAssertFalse(service.unloadShortcutHostedSplitGroup(
                    fixture.group,
                    in: fixture.window
                ))
            }
        }

        XCTAssertTrue(service.unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.window
        ))

        XCTAssertEqual(oracle.windowCallbacks, 1)
        XCTAssertEqual(oracle.failures, 0)
        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(compositorRefreshCount, 1)
    }

    func testTopologyOnlyDeletionCommitsWithExactDetachedRuntime() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pins = try (0..<3).map { index in
            try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(index: index, spaceID: space.id),
                at: index
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.enumerated().map { index, pin in
                .shortcutPin(
                    pin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: index
                    )
                )
            },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(
            group, persist: false
        ))
        let remaining = try XCTUnwrap(
            group.removingMember(.shortcutPin(pins[0].id))
        )
        tabManager.detachBrowserRuntime()

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pins[0])

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(
            by: pins[0].id
        ))
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            remaining
        )
    }

    func testEmptyDeletedPinBatchPublishesNoModelOrRuntimeEffect() throws {
        let fixture = try PublicationFixture(pinCount: 3)
        var structuralEvents = 0
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in structuralEvents += 1 }
        let sourceGroup = fixture.group
        let sourceWindow = fixture.window.unpublishedShortcutMutationState

        let prepared = try XCTUnwrap(fixture.tabManager
            .shortcutLiveTabRetirement.prepareDeletedPinRetirements([]))
        _ = fixture.tabManager.shortcutLiveTabRetirement.finish(prepared)
        _ = fixture.tabManager.shortcutLiveTabRetirement.finish(prepared)

        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: sourceGroup.id),
            sourceGroup
        )
        XCTAssertEqual(
            fixture.window.unpublishedShortcutMutationState,
            sourceWindow
        )
        XCTAssertEqual(fixture.tabManager.liveShortcutTabs.entries(
            for: fixture.pins[0].id
        ).count, 1)
        _ = cancellable
    }
}
