import AppKit
import Combine
import Observation
import SumiDomain
import WebKit
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
        let runtime = TestRuntimePorts.make(
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
        tabManager = BrowserManager(runtimePorts: runtime)
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
        let compositorContainer = NSView()
        tabs.webViewRuntime.compositorRuntime.registerContainer(
            compositorContainer,
            for: fixture.window.id,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )
        let compositorVersion = fixture.window.compositorInvalidation
            .compositorVersion
        let service = makeHostedSplitUnload(for: tabs)
        let oracle = PublicationOracle()
        let windowPublished = expectation(
            description: "Window publishes its terminal hosted-split state"
        )
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
                windowPublished.fulfill()
                XCTAssertNil(service.unloadShortcutHostedSplitGroup(
                    fixture.group,
                    in: fixture.window
                ))
            }
        }

        XCTAssertEqual(service.unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.window
        )?.unloadedTabCount, 2)

        await fulfillment(of: [windowPublished], timeout: 1)
        XCTAssertEqual(oracle.windowCallbacks, 1)
        XCTAssertEqual(oracle.failures, 0)
        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(
            fixture.window.compositorInvalidation.compositorVersion,
            compositorVersion + 1
        )
        withExtendedLifetime(compositorContainer) {}
    }

    func testHostedSplitUnloadRestoresWholeRegularSplit() throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let browser = fixture.browser
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        let space = try XCTUnwrap(
            browser.spaceStateOwner.space(with: spaceID)
        )
        let first = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://split-first.example",
            in: space,
            activate: false
        )
        let second = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://split-second.example",
            in: space,
            activate: false
        )
        let fallbackGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(first.id),
                .regularTab(second.id),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(
            fallbackGroup,
            persist: false
        ))
        fixture.window.selectionHistory.recentRegularTabIdsBySpace[space.id] = [
            second.id,
            first.id,
        ]
        fixture.window.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(fixture.pins[0].id),
            .regularTab(second.id),
            .regularTab(first.id),
        ]
        let service = makeHostedSplitUnload(for: browser)

        XCTAssertEqual(service.unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.window
        )?.unloadedTabCount, 2)

        XCTAssertEqual(fixture.window.currentTabId, second.id)
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: fallbackGroup.id,
                activeMemberID: .regularTab(second.id)
            )
        )
        guard case .ready(let presentation) = browser.splitQuery.resolution(
            in: fixture.window.id
        ) else {
            return XCTFail("Expected the previous split group presentation")
        }
        XCTAssertEqual(presentation.groupID, fallbackGroup.id)
        XCTAssertEqual(Set(presentation.visibleTabIDs), [first.id, second.id])
    }

    func testHostedSplitUnloadHandsOffToPreviousFavorite() throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let profileID = try XCTUnwrap(fixture.window.currentProfileId)
        let favoritePin = try XCTUnwrap(
            fixture.browser.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .favorite,
                    profileId: profileID,
                    index: 0,
                    launchURL: try XCTUnwrap(
                        URL(string: "https://favorite.example")
                    ),
                    title: "Favorite"
                ),
                at: 0
            )
        )
        let favoriteTab = try XCTUnwrap(
            fixture.browser.shortcutTabMaterializer.materialize(
                favoritePin,
                in: fixture.window.id,
                currentSpaceId: fixture.window.currentSpaceId
            )
        )
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        fixture.window.selectionHistory.recentSelectionItemsBySpace[spaceID] = [
            .shortcutPin(fixture.pins[0].id),
            .shortcutPin(favoritePin.id),
        ]

        XCTAssertEqual(
            makeHostedSplitUnload(for: fixture.browser)
                .unloadShortcutHostedSplitGroup(
                    fixture.group,
                    in: fixture.window
                )?.unloadedTabCount,
            2
        )

        XCTAssertEqual(fixture.window.currentTabId, favoriteTab.id)
        XCTAssertEqual(
            fixture.window.currentShortcutPinId,
            favoritePin.id
        )
        XCTAssertNil(fixture.window.splitSelection)
        XCTAssertFalse(fixture.window.isShowingEmptyState)
    }

    func testBackgroundHostedSplitUnloadPreservesForegroundLauncherAndWebView()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let browser = fixture.browser
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        let foregroundPin = try XCTUnwrap(
            browser.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(index: 99, spaceID: spaceID),
                at: 2
            )
        )
        let foregroundTab = try XCTUnwrap(
            browser.shortcutTabMaterializer.materialize(
                foregroundPin,
                in: fixture.window.id,
                currentSpaceId: spaceID
            )
        )
        let foregroundWebView = WKWebView()
        foregroundTab.replaceUntrackedWebView(foregroundWebView)
        fixture.window.currentTabId = foregroundTab.id
        fixture.window.currentShortcutPinId = foregroundPin.id
        fixture.window.currentShortcutPinRole = foregroundPin.role
        fixture.window.splitSelection = nil
        fixture.window.isShowingEmptyState = false
        var handoffCount = 0
        let compositorContainer = NSView()
        browser.webViewRuntime.compositorRuntime.registerContainer(
            compositorContainer,
            for: fixture.window.id,
            immediateVisualHandoffHandler: {
                handoffCount += 1
                return true
            }
        )
        let service = makeHostedSplitUnload(for: browser)

        XCTAssertEqual(
            service.unloadShortcutHostedSplitGroup(
                fixture.group,
                in: fixture.window
            )?.unloadedTabCount,
            2
        )

        XCTAssertEqual(fixture.window.currentTabId, foregroundTab.id)
        XCTAssertEqual(
            fixture.window.currentShortcutPinId,
            foregroundPin.id
        )
        XCTAssertNil(fixture.window.splitSelection)
        XCTAssertFalse(fixture.window.isShowingEmptyState)
        XCTAssertIdentical(
            foregroundTab.resolvedCurrentWebView(),
            foregroundWebView
        )
        XCTAssertEqual(handoffCount, 0)
        withExtendedLifetime(compositorContainer) {}
    }

    func testBackgroundHostedSplitUnloadPreservesForegroundSplitGroup()
        throws {
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let browser = fixture.browser
        let spaceID = try XCTUnwrap(fixture.window.currentSpaceId)
        let foregroundPins = try (2..<4).map { index in
            try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(index: index, spaceID: spaceID),
                at: index
            ))
        }
        let foregroundTabs = try foregroundPins.map { pin in
            try XCTUnwrap(browser.shortcutTabMaterializer.materialize(
                pin,
                in: fixture.window.id,
                currentSpaceId: spaceID
            ))
        }
        let foregroundGroup = try XCTUnwrap(SplitGroup.make(
            members: foregroundPins.map { .shortcutPin($0.id) },
            layoutKind: .horizontal,
            container: .shortcutSidebar(
                spaceId: spaceID,
                profileId: nil,
                folderId: nil,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(
            foregroundGroup,
            persist: false
        ))
        let foregroundWebView = WKWebView()
        foregroundTabs[0].replaceUntrackedWebView(foregroundWebView)
        fixture.window.currentTabId = foregroundTabs[0].id
        fixture.window.currentShortcutPinId = foregroundPins[0].id
        fixture.window.currentShortcutPinRole = foregroundPins[0].role
        fixture.window.splitSelection = WindowSplitSelection(
            groupID: foregroundGroup.id,
            activeMemberID: .shortcutPin(foregroundPins[0].id)
        )

        XCTAssertEqual(
            makeHostedSplitUnload(for: browser)
                .unloadShortcutHostedSplitGroup(
                    fixture.group,
                    in: fixture.window
                )?.unloadedTabCount,
            2
        )

        XCTAssertEqual(fixture.window.currentTabId, foregroundTabs[0].id)
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: foregroundGroup.id,
                activeMemberID: .shortcutPin(foregroundPins[0].id)
            )
        )
        XCTAssertIdentical(
            foregroundTabs[0].resolvedCurrentWebView(),
            foregroundWebView
        )
        guard case .ready(let presentation) = browser.splitQuery.resolution(
            in: fixture.window.id
        ) else {
            return XCTFail("Expected foreground Split Group presentation")
        }
        XCTAssertEqual(presentation.groupID, foregroundGroup.id)
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
            pins: browser.shortcutPinCollectionStateOwner,
            pinCommands: browser.sidebarPinCommands,
            hostedUnload: makeHostedSplitUnload(for: browser),
            membership: browser.tabCollectionMembershipOwner,
            close: browser.tabCloseOrchestration,
            notifications: browser.notificationPresenter
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

    func testDeletingLoadedHostedSplitRetiresGroupPinsAndRuntime() throws {
        let notifications = NotificationPresentingSpy()
        let fixture = try PublicationFixture(
            pinCount: 2,
            hostedSplit: true
        )
        let browser = fixture.browser
        let lifecycle = SidebarSplitGroupLifecycleCommands(
            groups: browser.splitGroupStore,
            pins: browser.shortcutPinCollectionStateOwner,
            pinCommands: browser.sidebarPinCommands,
            hostedUnload: makeHostedSplitUnload(for: browser),
            membership: browser.tabCollectionMembershipOwner,
            close: browser.tabCloseOrchestration,
            notifications: notifications
        )

        lifecycle.deleteSaved(fixture.group, in: fixture.window)

        XCTAssertNil(browser.splitGroupStore.group(id: fixture.group.id))
        XCTAssertTrue(fixture.pins.allSatisfy {
            browser.shortcutPinCollectionStateOwner.shortcutPin(by: $0.id)
                == nil
        })
        XCTAssertTrue(fixture.liveTabs.allSatisfy {
            browser.liveShortcutTabs.entry(tabId: $0.id) == nil
                && browser.tabCollectionMembershipOwner.tab(for: $0.id) == nil
        })
        XCTAssertNil(fixture.window.splitSelection)
        XCTAssertEqual(
            notifications.presentSavedSplitViewDeletionNotificationCalls
                .map(\.count),
            [2]
        )
        XCTAssertEqual(
            notifications.presentSavedSplitViewDeletionNotificationCalls
                .first?.windowState?.id,
            fixture.window.id
        )
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
        let profile = Profile(name: "Topology")
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            )
        ))
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
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
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(
            group, persist: false
        ))
        let remaining = try XCTUnwrap(
            group.removingMember(.shortcutPin(pins[0].id))
        )
        let removedPin = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(
                by: pins[0].id
            )
        )
        XCTAssertTrue(tabManager.sidebarPinCommands.remove(removedPin))

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

    private func makeHostedSplitUnload(
        for browser: BrowserManager
    ) -> ShortcutHostedSplitUnloadService {
        ShortcutHostedSplitUnloadService(
            planner: ShortcutHostedSplitUnloadPlanner(
                runtimeConnection: browser.runtimePortConnection,
                groups: browser.splitGroupStore,
                fallbackPlanner: BrowserTabCloseFallbackPlanner(
                    selectionService: browser.windowSelectionProjection,
                    tabStore: browser.runtimeStore
                ),
                splitMembership: browser.splitGroupMembership
            ),
            retirement: browser.shortcutLiveTabRetirement,
            visuals: browser.shellRuntime.windowVisuals
        )
    }
}
