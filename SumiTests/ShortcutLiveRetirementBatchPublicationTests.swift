import AppKit
import Combine
import Observation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveRetirementBatchPublicationTests: XCTestCase {
    func testFixtureWindowQueriesShareExactIdentity() throws {
        let fixture = try PublicationFixture(pinCount: 2)
        let runtime = fixture.browser.runtimePortConnection.requireLease()
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
        let cancellable = fixture.browser.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                oracle.structuralCallbacks += 1
                oracle.assertTerminal(
                    fixture: fixture,
                    removedPin: removedPin,
                    removedTab: removedTab,
                    remaining: remaining
                )
                let repeated = fixture.browser.shortcutLiveTabRetirement
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

        XCTAssertTrue(fixture.browser.sidebarPinCommands.remove(removedPin))

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
        var tabManager: BrowserManager!
        tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
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
        ))
        let space = try makeSpace(in: tabManager)
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
                    fixture.browser.folderCollectionStateOwner.folder(
                        by: folder.id
                    )
                )
                XCTAssertTrue(fixture.pins.allSatisfy {
                    fixture.browser.shortcutPinCollectionStateOwner
                        .shortcutPin(by: $0.id) == nil
                })
                XCTAssertTrue(fixture.liveTabs.allSatisfy {
                    fixture.browser.liveShortcutTabs.entry(tabId: $0.id)
                        == nil
                        && fixture.browser.tabCollectionMembershipOwner
                            .tab(for: $0.id) == nil
                })
                XCTAssertNil(fixture.browser.splitGroupStore.group(
                    id: fixture.group.id
                ))
                XCTAssertNil(fixture.window.splitSelection)
                XCTAssertNotEqual(
                    fixture.window.currentShortcutPinId,
                    removedPin.id
                )
                XCTAssertNil(fixture.browser.liveShortcutTabs.entry(
                    tabId: removedTab.id
                ))
            }
        }

        XCTAssertTrue(fixture.browser.sidebarFolderCommands.deleteFolder(folder.id))

        XCTAssertEqual(oracle.windowCallbacks, 1)
    }

    func testHostedSplitFirstWindowCallbackSeesTerminalEmptyPresentation()
        async throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        var handoffCount = 0
        let tabs = fixture.browser
        tabs.webViewRuntime.compositorRuntime.registerContainer(
            NSView(),
            for: fixture.window.id,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )
        let compositorVersion = fixture.window.compositorInvalidation
            .compositorVersion
        let service = ShortcutHostedSplitUnloadService(
            runtimeConnection: tabs.runtimePortConnection,
            splitGroups: tabs.splitGroupStore,
            retirement: tabs.shortcutLiveTabRetirement,
            fallback: ShortcutHostedSplitFallbackQuery(
                spaces: tabs.spaceStateOwner,
                regularTabs: tabs.regularTabCollectionOwner
            ),
            visuals: tabs.shellRuntime.windowVisuals
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
                        fixture.browser.liveShortcutTabs.entry(
                            tabId: tab.id
                        ) == nil
                            && fixture.browser.tabCollectionMembershipOwner
                                .tab(for: tab.id) == nil
                    }
                    && fixture.browser.splitGroupStore.group(
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
        await Task.yield()
        XCTAssertEqual(
            fixture.window.compositorInvalidation.compositorVersion,
            compositorVersion + 1
        )
    }

    func testFolderSplitUnloadRetiresWholeGroupWithoutCollapsingFolder()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            foldered: true,
            hostedSplit: true
        )
        let folder = try XCTUnwrap(fixture.folder)
        folder.isOpen = true
        let browser = fixture.browser
        let lifecycle = SidebarSplitGroupLifecycleCommands(
            groups: browser.splitGroupStore,
            mutations: browser.splitGroupMutations,
            pins: browser.shortcutPinCollectionStateOwner,
            pinCommands: browser.sidebarPinCommands,
            hostedUnload: ShortcutHostedSplitUnloadService(
                runtimeConnection: browser.runtimePortConnection,
                splitGroups: browser.splitGroupStore,
                retirement: browser.shortcutLiveTabRetirement,
                fallback: ShortcutHostedSplitFallbackQuery(
                    spaces: browser.spaceStateOwner,
                    regularTabs: browser.regularTabCollectionOwner
                ),
                visuals: browser.shellRuntime.windowVisuals
            ),
            membership: browser.tabCollectionMembershipOwner,
            close: browser.tabCloseOrchestration,
            structuralLookup: browser.structuralLookupCoordinator
        )

        lifecycle.unload(
            fixture.group,
            in: fixture.window
        )

        XCTAssertTrue(folder.isOpen)
        XCTAssertEqual(
            fixture.browser.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
        XCTAssertEqual(
            fixture.group.container.shortcutSidebarFolderId,
            folder.id
        )
        XCTAssertTrue(fixture.pins.allSatisfy { $0.folderId == folder.id })
        XCTAssertTrue(fixture.liveTabs.allSatisfy { tab in
            fixture.browser.liveShortcutTabs.entry(tabId: tab.id) == nil
        })
        XCTAssertNil(fixture.window.splitSelection)
    }

    func testCollapsedFolderResetUnloadsHostedSplitGroup() throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            foldered: true,
            hostedSplit: true
        )
        let browser = fixture.browser
        let folder = try XCTUnwrap(fixture.folder)
        let spaceID = try XCTUnwrap(fixture.pins.first?.spaceId)
        let space = try XCTUnwrap(browser.spaceStateOwner.space(with: spaceID))
        let context = browser.composeSidebarBrowserContext(
            spaceLifecycle: browser.sidebarSpaceLifecycle
        )
        let inventory = SidebarPinnedInventoryProjection(
            folders: browser.folderCollectionStateOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            splitGroups: browser.splitGroupStore,
            splitOrdering: browser.splitGroupSidebarOrdering
        ).snapshot(for: spaceID, regularTabs: [])
        let actions = TabFolderMutationActions(
            browserContext: context,
            pinExecution: SidebarPinExecutionCommands(
                runtime: browser.runtimePortConnection,
                windows: SidebarWindowIdentityQuery(
                    registry: browser.windowRegistry
                ),
                pins: browser.shortcutPinCollectionStateOwner,
                materializer: browser.shortcutTabMaterializer,
                profiles: browser.shortcutExecutionProfileAssignments
            ),
            folderCommands: browser.sidebarFolderCommands,
            windowState: fixture.window,
            windowRegistry: browser.windowRegistry,
            themeContext: .default,
            space: space,
            folderLayoutAnimation: nil
        )

        actions.resetCollapsedProjection(folder, inventory: inventory)

        XCTAssertEqual(
            browser.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
        XCTAssertTrue(fixture.liveTabs.allSatisfy { tab in
            browser.liveShortcutTabs.entry(tabId: tab.id) == nil
                && browser.tabCollectionMembershipOwner.tab(for: tab.id) == nil
        })
        XCTAssertNil(fixture.window.splitSelection)
    }

    func testTopologyOnlyDeletionCommitsWithExactDetachedRuntime() throws {
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make())
        let space = try makeSpace(in: tabManager)
        let pins = try (0..<3).map { index in
            try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(index: index, spaceID: space.id),
                at: index
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { pin in
                .shortcutPin(pin.id)
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
        tabManager.runtimePortConnection.detach()

        XCTAssertTrue(tabManager.sidebarPinCommands.remove(pins[0]))

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
        let cancellable = fixture.browser.tabStructureEventBus
            .structureChangedPublisher.sink { _ in structuralEvents += 1 }
        let sourceGroup = fixture.group
        let sourceWindow = fixture.window.unpublishedShortcutMutationState

        let prepared = try XCTUnwrap(fixture.browser
            .shortcutLiveTabRetirement.prepareDeletedPinRetirements([]))
        _ = fixture.browser.shortcutLiveTabRetirement.finish(prepared)
        _ = fixture.browser.shortcutLiveTabRetirement.finish(prepared)

        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(
            fixture.browser.splitGroupStore.group(id: sourceGroup.id),
            sourceGroup
        )
        XCTAssertEqual(
            fixture.window.unpublishedShortcutMutationState,
            sourceWindow
        )
        XCTAssertEqual(fixture.browser.liveShortcutTabs.entries(
            for: fixture.pins[0].id
        ).count, 1)
        _ = cancellable
    }

    private func makeSpace(in browser: BrowserManager) throws -> Space {
        try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
    }
}
