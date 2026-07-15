import Combine
import Observation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class RegularTabShortcutConversionServiceTests: XCTestCase {
    func testSplitConversionReplacesDurableTabWithPinAndProjectsEachWindow() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        var visibleIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { _ in visibleIds },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example/source",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example/companion",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        visibleIds = [source.id, companion.id]
        for windowState in [first, second] {
            windowState.currentSpaceId = space.id
            windowState.currentTabId = source.id
            windowState.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(source.id)
            )
        }

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                source,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: second.id
            )
        )

        let replacement = try XCTUnwrap(
            tabManager.splitGroupStore.group(id: group.id)
        )
        XCTAssertTrue(replacement.contains(.shortcutPin(pin.id)))
        XCTAssertFalse(replacement.contains(.regularTab(source.id)))
        XCTAssertEqual(
            first.splitSelection?.activeMemberID,
            .shortcutPin(pin.id)
        )
        XCTAssertEqual(
            second.splitSelection?.activeMemberID,
            .shortcutPin(pin.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: first.id),
            source
        )
        XCTAssertNotNil(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: second.id)
        )
    }

    func testDisplayedConversionPublicationSeesTerminalModelAndPreservesReentrantSplitMutation() throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let states = [primary.id: primary, secondary.id: secondary]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primary.id }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://conversion-publication.example/source",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://conversion-publication.example/companion",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        for state in [primary, secondary] {
            state.currentSpaceId = space.id
            state.currentTabId = source.id
            state.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(source.id)
            )
        }

        let observation = DisplayedConversionWindowObservationOracle()
        var structuralEvents = 0
        let structureCancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        withObservationTracking {
            for state in [primary, secondary] {
                _ = state.currentTabId
                _ = state.currentShortcutPinId
                _ = state.splitSelection
                _ = state.activeTabForSpace
                _ = state.selectedShortcutPinForSpace
                _ = state.selectionHistory
            }
        } onChange: {
            MainActor.assumeIsolated {
                guard observation.didInspectFirstPublication == false else {
                    return
                }
                observation.didInspectFirstPublication = true
                let pins = tabManager.shortcutPinCollectionStateOwner
                    .spacePinnedPins(for: space.id)
                guard let pin = pins.first,
                      pins.count == 1,
                      let terminalGroup = tabManager.splitGroupStore.group(
                          id: group.id
                      ) else {
                    return XCTFail(
                        "First window publication must expose terminal catalog and topology"
                    )
                }
                observation.observedPinID = pin.id
                XCTAssertTrue(terminalGroup.contains(.shortcutPin(pin.id)))
                XCTAssertFalse(
                    terminalGroup.contains(.regularTab(source.id))
                )
                XCTAssertFalse(
                    tabManager.regularTabCollectionOwner.contains(source)
                )
                XCTAssertIdentical(
                    tabManager.liveShortcutTabs.tab(
                        for: pin.id,
                        in: primary.id
                    ),
                    source
                )
                for state in [primary, secondary] {
                    let liveTab = tabManager.liveShortcutTabs.tab(
                        for: pin.id,
                        in: state.id
                    )
                    XCTAssertEqual(state.currentTabId, liveTab?.id)
                    XCTAssertEqual(state.currentShortcutPinId, pin.id)
                    XCTAssertEqual(
                        state.splitSelection,
                        WindowSplitSelection(
                            groupID: group.id,
                            activeMemberID: .shortcutPin(pin.id)
                        )
                    )
                }
                guard let horizontal = terminalGroup.changingLayout(
                    to: .horizontal
                ) else {
                    return XCTFail(
                        "Expected a valid reentrant layout mutation"
                    )
                }
                let expected = tabManager.splitGroupStore.groups
                let replacement = expected.map {
                    $0.id == horizontal.id ? horizontal : $0
                }
                observation.didCommitReentrantMutation = tabManager
                    .splitGroupMutations.replaceAll(
                        expected: expected,
                        with: replacement,
                        persist: false
                    )
                observation.reentrantReplacement = horizontal
            }
        }
        structuralEvents = 0

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                source,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: secondary.id
            )
        )

        XCTAssertTrue(observation.didInspectFirstPublication)
        XCTAssertEqual(observation.observedPinID, pin.id)
        XCTAssertTrue(observation.didCommitReentrantMutation)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            observation.reentrantReplacement
        )
        XCTAssertEqual(structuralEvents, 1)
        _ = structureCancellable
    }

    func testPrimarySelectedWindowKeepsOriginalAndSecondaryMaterializesAfterCommit() throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let states = [primary.id: primary, secondary.id: secondary]
        var structuralEvents = 0
        var eventsSeenAtMaterialization: [Int] = []
        var materialized: [(UUID, UUID)] = []
        var cancellable: AnyCancellable?
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { tabId in
                primary.currentTabId == tabId ? primary.id : nil
            },
            materializeVisibleTabWebViewIfNeeded: { tab, window in
                eventsSeenAtMaterialization.append(structuralEvents)
                materialized.append((tab.id, window.id))
            }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://convert.example",
            in: space,
            activate: false
        )
        primary.currentSpaceId = space.id
        secondary.currentSpaceId = space.id
        primary.currentTabId = tab.id
        secondary.currentTabId = tab.id
        cancellable = tabManager.tabStructureEventBus.structureChangedPublisher
            .sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: secondary.id
            )
        )

        let secondaryTab = try XCTUnwrap(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: secondary.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: primary.id),
            tab
        )
        XCTAssertNotEqual(secondaryTab.id, tab.id)
        XCTAssertEqual(primary.currentTabId, tab.id)
        XCTAssertEqual(secondary.currentTabId, secondaryTab.id)
        XCTAssertEqual(materialized.map(\.0), [secondaryTab.id])
        XCTAssertEqual(materialized.map(\.1), [secondary.id])
        XCTAssertEqual(eventsSeenAtMaterialization, [1])
        XCTAssertEqual(structuralEvents, 1)
        _ = cancellable
    }

    func testSplitVisibleInAnotherWindowRejectsConversionWithoutPartialMutation() throws {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let states = [selected.id: selected, splitOnly.id: splitOnly]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnly.id ? [selected.currentTabId].compactMap(\.self) : []
            }
        )
        selected.tabManager = tabManager
        splitOnly.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let original = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/original",
            in: space,
            activate: false
        )
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/fallback",
            in: space,
            activate: false
        )
        selected.currentSpaceId = space.id
        selected.currentTabId = original.id
        splitOnly.currentSpaceId = space.id
        splitOnly.currentTabId = fallback.id
        splitOnly.activeTabForSpace[space.id] = original.id
        splitOnly.selectionHistory.recordRegularTabSelection(
            original.id,
            in: space.id
        )
        XCTAssertNil(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                original,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: selected.id
            )
        )

        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(original))
        XCTAssertFalse(original.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertEqual(splitOnly.currentTabId, fallback.id)
        XCTAssertEqual(splitOnly.activeTabForSpace[space.id], original.id)
        XCTAssertEqual(
            splitOnly.selectionHistory.recentRegularTabIdsBySpace[space.id]?
                .contains(original.id),
            true
        )
    }

    func testPrimaryLeaseChangeRejectsPreparedConversionWithoutMutation() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        var primaryWindowId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primaryWindowId },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://primary-lease.example",
            in: space,
            activate: false
        )
        for window in [first, second] {
            window.currentSpaceId = space.id
            window.currentTabId = tab.id
        }
        primaryWindowId = first.id
        let preparation = tabManager.regularTabShortcutConversion.prepare(
            tab,
            preferredWindowId: second.id
        )
        guard case .displayed = preparation else {
            return XCTFail("Expected displayed conversion preparation")
        }
        let firstSession = ShortcutConversionWindowSessionState(first)
        let secondSession = ShortcutConversionWindowSessionState(second)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        primaryWindowId = second.id
        let converted = tabManager.regularTabShortcutConversion.commit(
            tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: true
            )
        )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(first),
            firstSession
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(second),
            secondSession
        )
        _ = cancellable
    }

    func testPlanPreparedForAnotherTabRejectsBeforeStructuralMutation() throws {
        let window = BrowserWindowState()
        var visibleSplitIds: [UUID] = []
        var sourceTabId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            visibleSplitTabIds: { $0 == window.id ? visibleSplitIds : [] },
            primaryTrackedWindowId: { tabId in
                tabId == sourceTabId ? window.id : nil
            },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-source.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-companion.example",
            in: space,
            activate: false
        )
        let other = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-other.example",
            in: space,
            activate: false
        )
        sourceTabId = source.id
        window.tabManager = tabManager
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(source.id),
                    .regularTab(companion.id),
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        visibleSplitIds = group.memberIDs.compactMap { memberId in
            guard case .regularTab(let tabId) = memberId else { return nil }
            return tabId
        }
        XCTAssertTrue(tabManager.splitGroupMutations.insert(
            group,
            persist: false
        ))
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(
                source,
                preferredWindowId: window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid displayed conversion plan")
        }
        let windowSession = ShortcutConversionWindowSessionState(window)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let converted = tabManager.regularTabShortcutConversion
            .commit(
                other,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(other))
        XCTAssertFalse(source.isShortcutLiveInstance)
        XCTAssertFalse(other.isShortcutLiveInstance)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            group
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(window),
            windowSession
        )
        _ = cancellable
    }

    func testNoDisplayingWindowPreparesDetachedConversionWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden.example",
            in: space,
            activate: false
        )
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(tab)

        guard case .detached(let plan) = preparation else {
            return XCTFail("Expected a detached conversion plan")
        }
        XCTAssertEqual(plan.sourceTabId, tab.id)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
    }

    func testDetachedConversionRejectsBlockedPhysicalCleanupAtomically() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://blocked.example",
            in: space,
            activate: false
        )
        var cleanupRuntime = TabWebViewCleanupRuntime.inactive
        cleanupRuntime.removeAllWebViews = { _, _, _ in
            WebViewTabTeardownResult(
                discoveredWebViewCount: 1,
                cleanedWebViewCount: 0,
                deferredWebViewCount: 0,
                unscheduledProtectedWebViewCount: 0,
                blockedWebViewCount: 1
            )
        }
        tab.navigationRuntime.webViewCleanupRuntime = cleanupRuntime
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let revisionBefore = tabManager.structuralLookupCoordinator
            .mutationRevision
        let dirtyBefore = tabManager.structuralPersistence.dirtySet

        let converted = tabManager.shortcutPinCommandOwner
            .convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )

        XCTAssertNil(converted)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: tab.id),
            tab
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revisionBefore
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtyTabIds,
            dirtyBefore.dirtyTabIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds,
            dirtyBefore.dirtySpaceIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.deletedTabIds,
            dirtyBefore.deletedTabIds
        )
        _ = cancellable
    }

    func testDetachedPostStagingDriftRestoresRuntimeWithoutCleanupOrPersistence()
        throws {
        let repository = WebViewSessionRepository()
        var canRetireCalls = 0
        var beginCommittedCalls = 0
        var destroyCalls = 0
        var terminalDestroyCalls = 0
        var cleanupCalls = 0
        var persistedWindowIDs: [UUID] = []
        var injectTopologyDrift: (() -> Void)?
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .init(
                canRetire: { _ in
                    canRetireCalls += 1
                    if canRetireCalls == 2 { injectTopologyDrift?() }
                    return true
                },
                beginCommitted: { _ in
                    beginCommittedCalls += 1
                    return true
                },
                destroy: { _ in destroyCalls += 1 },
                destroyAfterTerminalDrain: { _ in
                    terminalDestroyCalls += 1
                }
            ),
            requireRemoveAllWebViews: { _, _ in cleanupCalls += 1 }
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: TestRuntimePorts.make(
                webViewLifecycle: lifecycle,
                persistWindowSession: {
                    persistedWindowIDs.append($0.id)
                }
            ),
            context: container.mainContext,
            webViewSessions: repository,
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let webView = WKWebView()
        let source = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tabManager.regularTabCollectionOwner.insert(
            source,
            in: space.id,
            at: 0
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://detached-stage.example/companion",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let drifted = try XCTUnwrap(group.changingLayout(to: .horizontal))
        injectTopologyDrift = {
            tabManager.splitGroupStore.replaceAll(with: [drifted])
        }
        let sourceGeneration = source.webViewSession.generation
        let dirtyBefore = tabManager.structuralPersistence.dirtySet
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let converted = tabManager.shortcutPinCommandOwner
            .convertTabToShortcutPin(
                source,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )

        XCTAssertNil(converted)
        XCTAssertEqual(canRetireCalls, 2)
        XCTAssertEqual(beginCommittedCalls, 0)
        XCTAssertEqual(destroyCalls, 0)
        XCTAssertEqual(terminalDestroyCalls, 0)
        XCTAssertEqual(cleanupCalls, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(repository.residence(of: webView), .parked(tabID: source.id))
        XCTAssertIdentical(source.webViewSession.parkedWebView, webView)
        XCTAssertEqual(source.webViewSession.generation, sourceGeneration)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.containsIdentical(
            source,
            in: space.id
        ))
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: source.id),
            source
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(tabManager.splitGroupStore.groups, [drifted])
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtyTabIds,
            dirtyBefore.dirtyTabIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds,
            dirtyBefore.dirtySpaceIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.deletedTabIds,
            dirtyBefore.deletedTabIds
        )
        _ = cancellable
    }

    func testShortcutSidebarDropMovesStableMemberAndEveryWindowToTargetGroup() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/source",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/companion",
            in: space,
            activate: false
        )
        let firstPin = Self.pin(spaceID: space.id, index: 0)
        let secondPin = Self.pin(spaceID: space.id, index: 1)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [firstPin, secondPin],
            for: space.id
        )
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(
                    firstPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 0
                    )
                ),
                .shortcutPin(
                    secondPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 1
                    )
                ),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.replaceAll(
            expected: [],
            with: [sourceGroup, targetGroup],
            persist: false
        ))
        for state in [first, second] {
            state.currentSpaceId = space.id
            state.currentTabId = source.id
            state.splitSelection = WindowSplitSelection(
                groupID: sourceGroup.id,
                activeMemberID: .regularTab(source.id)
            )
        }

        let prepared = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .prepareShortcutSidebarDrop(
                    source,
                    into: targetGroup,
                    preferredWindowId: second.id
                )
        )
        let replacementTarget = try XCTUnwrap(targetGroup.inserting(
            prepared.member,
            relativeTo: .shortcutPin(firstPin.id),
            side: .right
        ))
        let replacement = prepared.expectedSplitGroups.compactMap { group in
            if group.id == sourceGroup.id {
                return group.removingMember(.regularTab(source.id))
            }
            return group.id == targetGroup.id ? replacementTarget : group
        }
        let pin = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .commitShortcutSidebarDrop(
                    prepared,
                    replacingSplitGroupsWith: replacement,
                    sidebarMutation: .noChange
                )
        )

        XCTAssertEqual(pin.id, prepared.candidatePin.id)
        XCTAssertNil(tabManager.splitGroupStore.group(id: sourceGroup.id))
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: targetGroup.id),
            replacementTarget
        )
        guard case .generatedSpacePinnedFromRegular(let restoredSpaceID, _) =
            replacementTarget.member(for: prepared.member.memberID)?
                .returnPlacement else {
            return XCTFail("Expected generated regular-tab return placement")
        }
        XCTAssertEqual(restoredSpaceID, space.id)
        for state in [first, second] {
            XCTAssertEqual(state.splitSelection?.groupID, targetGroup.id)
            XCTAssertEqual(
                state.splitSelection?.activeMemberID,
                prepared.member.memberID
            )
            XCTAssertNotNil(
                tabManager.liveShortcutTabs.tab(for: pin.id, in: state.id)
            )
        }
    }

    func testStaleShortcutSidebarDropDoesNotInsertCandidatePin() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://sidebar-drop.example/stale",
            in: space,
            activate: false
        )
        let firstPin = Self.pin(spaceID: space.id, index: 0)
        let secondPin = Self.pin(spaceID: space.id, index: 1)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [firstPin, secondPin],
            for: space.id
        )
        let target = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(
                    firstPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 0
                    )
                ),
                .shortcutPin(
                    secondPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: 1
                    )
                ),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(target, persist: false))
        let prepared = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .prepareShortcutSidebarDrop(
                    source,
                    into: target,
                    preferredWindowId: UUID()
                )
        )
        let replacementTarget = try XCTUnwrap(target.inserting(
            prepared.member,
            relativeTo: .shortcutPin(firstPin.id),
            side: .right
        ))
        let replacement = prepared.expectedSplitGroups.map {
            $0.id == target.id ? replacementTarget : $0
        }
        let staleTarget = try XCTUnwrap(target.changingLayout(to: .horizontal))
        XCTAssertTrue(tabManager.splitGroupMutations.replace(
            target,
            with: staleTarget,
            persist: false
        ))

        XCTAssertNil(
            tabManager.regularTabShortcutConversion
                .commitShortcutSidebarDrop(
                    prepared,
                    replacingSplitGroupsWith: replacement,
                    sidebarMutation: .noChange
                )
        )
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(
                by: prepared.candidatePin.id
            )
        )
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertEqual(tabManager.splitGroupStore.group(id: target.id), staleTarget)
    }

    private static func pin(spaceID: UUID, index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceID,
            index: index,
            launchURL: URL(string: "https://sidebar-pin-\(index).example")!,
            title: "Pin \(index)"
        )
    }
}

@MainActor
private final class DisplayedConversionWindowObservationOracle {
    var didInspectFirstPublication = false
    var observedPinID: UUID?
    var reentrantReplacement: SplitGroup?
    var didCommitReentrantMutation = false
}
