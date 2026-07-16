import Combine
import Observation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class RegularTabShortcutConversionServiceTests: XCTestCase {
    func testNilRuntimeDetachedConversionCommitsTerminalModelExactlyOnce() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://nil-runtime-conversion.example",
            in: space,
            activate: false
        )
        let lifecycleEvents = ConversionLifecycleCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: tab,
            queue: nil
        ) { _ in lifecycleEvents.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        tabManager.runtimePortsAttachmentOwner.detach()

        let pin = try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                )
            )
        )

        XCTAssertEqual(lifecycleEvents.count, 1)
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
        XCTAssertFalse(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id),
            pin
        )
        _ = cancellable
    }

    func testDetachedConversionRejectsSameIDMembershipDrift() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://membership-drift.example/source",
            in: space,
            activate: false
        )
        let preparation = tabManager.regularTabShortcutConversion.prepare(source)
        let replacement = tabManager.tabFactory.makeTab(
            id: source.id,
            url: URL(string: "https://membership-drift.example/replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tabManager.tabCollectionMembershipOwner.attach(replacement)

        let acceptance = tabManager.regularTabShortcutConversion.commit(
            source,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(acceptance)
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: source.id),
            replacement
        )
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
    }

    func testDetachedConversionRejectsRuntimeAttachmentDriftBeforeClaim()
        throws {
        let repository = WebViewSessionRepository()
        var canRetireCalls = 0
        var destroyCalls = 0
        var persistedWindowIDs: [UUID] = []
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .init(
                canRetire: { _ in
                    canRetireCalls += 1
                    return true
                },
                beginCommitted: { _ in true },
                committedRetirementIsExact: { _ in true },
                destroy: { _ in destroyCalls += 1 },
                destroyAfterTerminalDrain: { _ in destroyCalls += 1 }
            )
        )
        let runtimeA = TestRuntimePorts.make(
            webViewLifecycle: lifecycle,
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: runtimeA,
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
        tabManager.regularTabCollectionOwner.insert(source, in: space.id, at: 0)
        let preparation = tabManager.regularTabShortcutConversion.prepare(source)
        tabManager.runtimePortsAttachmentOwner.detach()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                webViewLifecycle: lifecycle,
                persistWindowSession: { persistedWindowIDs.append($0.id) }
            )
        )
        let dirtyBefore = tabManager.structuralPersistence.dirtySet
        let schedulingRevisionBefore = tabManager.structuralPersistence
            .schedulingRevision
        var structuralEvents = 0
        let structureCancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        let lifecycleEvents = ConversionLifecycleCounter()
        let lifecycleObserver = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: source,
            queue: nil
        ) { _ in lifecycleEvents.increment() }
        defer { NotificationCenter.default.removeObserver(lifecycleObserver) }

        let acceptance = tabManager.regularTabShortcutConversion.commit(
            source,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(acceptance)
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
        XCTAssertIdentical(source.webViewSession.parkedWebView, webView)
        XCTAssertEqual(repository.residence(of: webView), .parked(tabID: source.id))
        XCTAssertEqual(canRetireCalls, 0)
        XCTAssertEqual(destroyCalls, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(lifecycleEvents.count, 0)
        XCTAssertEqual(tabManager.structuralPersistence.dirtySet, dirtyBefore)
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            schedulingRevisionBefore
        )
        _ = structureCancellable
    }

    func testDetachedConversionPublishesStructureLifecycleThenPhysical()
        throws {
        let order = ConversionPublicationOrderOracle()
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            ),
            notifyTabClosedIfLoaded: { _ in order.record("physical") }
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://detached-order.example/source",
            in: space,
            activate: false
        )
        let replacement = tabManager.tabFactory.makeTab(
            id: source.id,
            url: URL(string: "https://detached-order.example/replacement")!,
            loadsCachedFaviconOnInit: false
        )
        let attachReplacement = MainActorTestAction {
            tabManager.tabCollectionMembershipOwner.attach(replacement)
        }
        let structureCancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { order.record("structure") }
        let lifecycleObserver = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: source,
            queue: nil
        ) { _ in
            order.record("lifecycle")
            attachReplacement.call()
        }
        defer { NotificationCenter.default.removeObserver(lifecycleObserver) }

        let pin = try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                source,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                )
            )
        )

        XCTAssertEqual(order.events, ["structure", "lifecycle", "physical"])
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: source.id),
            replacement
        )
        XCTAssertFalse(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id),
            pin
        )
        _ = structureCancellable
    }

    func testDetachedCommittedDestroyIsLastAndPreservesSameIDWebView()
        throws {
        let order = ConversionPublicationOrderOracle()
        let repository = WebViewSessionRepository()
        var persistedWindowIDs: [UUID] = []
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .init(
                canRetire: { _ in true },
                beginCommitted: { _ in true },
                committedRetirementIsExact: { _ in true },
                destroy: { _ in order.record("destroy") },
                destroyAfterTerminalDrain: { _ in
                    XCTFail("Normal commit used terminal-drain destruction")
                }
            )
        )
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: lifecycle,
            notifyTabClosedIfLoaded: { _ in order.record("extension") },
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: repository,
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let retiredWebView = WKWebView()
        let source = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: retiredWebView,
            loadsCachedFaviconOnInit: false
        )
        tabManager.regularTabCollectionOwner.insert(source, in: space.id, at: 0)
        let replacementWebView = WKWebView()
        let attachReplacement = MainActorTestAction {
            let replacement = tabManager.tabFactory.makeTab(
                id: source.id,
                spaceId: space.id,
                existingWebView: replacementWebView,
                loadsCachedFaviconOnInit: false
            )
            tabManager.tabCollectionMembershipOwner.attach(replacement)
        }
        let structureCancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { order.record("structure") }
        let lifecycleObserver = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: source,
            queue: nil
        ) { _ in
            order.record("lifecycle")
            attachReplacement.call()
        }
        defer { NotificationCenter.default.removeObserver(lifecycleObserver) }

        let pin = try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                source,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                )
            )
        )

        XCTAssertEqual(
            order.events,
            ["structure", "lifecycle", "extension", "destroy"]
        )
        let replacement = try XCTUnwrap(
            tabManager.tabCollectionMembershipOwner.tab(for: source.id)
        )
        XCTAssertFalse(replacement === source)
        XCTAssertIdentical(replacement.webViewSession.parkedWebView, replacementWebView)
        XCTAssertEqual(
            repository.residence(of: replacementWebView),
            .parked(tabID: source.id)
        )
        XCTAssertNil(repository.residence(of: retiredWebView))
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id),
            pin
        )
        _ = structureCancellable
    }

    func testDisplayedProfilelessConversionUsesCapturedDefaultProfile() throws {
        let window = BrowserWindowState()
        let fallbackProfile = Profile(name: "Fallback")
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { nil },
            defaultProfileId: { fallbackProfile.id },
            profile: { $0 == fallbackProfile.id ? fallbackProfile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            primaryTrackedWindowId: { _ in window.id }
        )
        window.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://profileless-conversion.example",
            in: space,
            activate: false
        )
        window.currentSpaceId = space.id
        window.currentTabId = tab.id

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: window.id
            )
        )

        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: window.id),
            tab
        )
    }

    func testSplitConversionReplacesDurableTabWithPinAndProjectsEachWindow() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [first.id: first, second.id: second]
        var visibleIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { _ in visibleIds },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
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
        let profile = Profile(name: "Runtime")
        let states = [primary.id: primary, secondary.id: secondary]
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primary.id }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
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
        let profile = Profile(name: "Runtime")
        let states = [primary.id: primary, secondary.id: secondary]
        var structuralEvents = 0
        var eventsSeenAtMaterialization: [Int] = []
        var materialized: [(UUID, UUID)] = []
        var cancellable: AnyCancellable?
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
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
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
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

    func testDisplayedQueuedMaterializationRejectsReattachedRuntime() throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [primary.id: primary, secondary.id: secondary]
        var originalMaterializations: [UUID] = []
        var replacementMaterializations: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primary.id },
            materializeVisibleTabWebViewIfNeeded: { tab, _ in
                originalMaterializations.append(tab.id)
            }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://runtime-lease.example",
            in: space,
            activate: false
        )
        for window in [primary, secondary] {
            window.currentSpaceId = space.id
            window.currentTabId = source.id
        }
        let replacementRuntime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                materializeVisibleTabWebViewIfNeeded: { tab, _ in
                    replacementMaterializations.append(tab.id)
                },
                primaryTrackedWindowId: { _ in primary.id }
            )
        )
        var didReattach = false
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                guard didReattach == false else { return }
                didReattach = true
                tabManager.runtimePortsAttachmentOwner.detach()
                tabManager.runtimePortsAttachmentOwner.attach(replacementRuntime)
            }

        let pin = tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
            source,
            role: .spacePinned,
            profileId: nil,
            spaceId: space.id,
            folderId: nil,
            at: 0,
            preferredWindowId: secondary.id
        )

        XCTAssertNotNil(pin)
        XCTAssertTrue(didReattach)
        XCTAssertTrue(originalMaterializations.isEmpty)
        XCTAssertTrue(replacementMaterializations.isEmpty)
        _ = cancellable
    }

    func testDisplayedForeignFreshSameIDQuarantinesConflictWithoutOverwrite()
        throws {
        try assertDisplayedForeignABA(target: .fresh)
    }

    func testDisplayedForeignSourceSameIDQuarantinesConflictWithoutOverwrite()
        throws {
        try assertDisplayedForeignABA(target: .source)
    }

    private func assertDisplayedForeignABA(
        target: DisplayedForeignABATarget
    ) throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [primary.id: primary, secondary.id: secondary]
        var tabManager: TabManager!
        var foreign: Tab?
        var source: Tab!
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            executePreparedProfileAssignments: {
                assignments, binding, settlement in
                let model = PreparedProfileAssignmentBatchModelTransaction(
                    assignments: assignments,
                    binding: binding
                )
                do {
                    try model.stage()
                } catch {
                    settlement(.rejected(.stale))
                    return .rejectedSettled
                }
                guard let source else {
                    XCTFail("Displayed conversion lost its source")
                    settlement(.conflicted)
                    return .conflicted
                }
                let replaced: Tab?
                switch target {
                case .source:
                    replaced = source
                case .fresh:
                    replaced = tabManager.transientTabRegistryOwner
                        .transientShortcutTabs.first { $0 !== source }
                }
                guard let replaced else {
                    XCTFail("Displayed conversion did not prepare its target")
                    settlement(.conflicted)
                    return .conflicted
                }
                let replacement = tabManager.tabFactory.makeTab(
                    id: replaced.id,
                    url: URL(string: "https://foreign-aba.example")!,
                    loadsCachedFaviconOnInit: false
                )
                foreign = replacement
                tabManager.tabCollectionMembershipOwner.attach(replacement)
                XCTAssertFalse(model.canClaimTerminalModel())
                do {
                    try model.rollback()
                    XCTFail("Rollback must reject foreign identity")
                } catch {}
                settlement(.conflicted)
                return .conflicted
            }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: lifecycle
        )
        let container = try makeInMemoryStartupModelContainer()
        tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
        source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://foreign-aba.example/source",
            in: space,
            activate: false
        )
        for window in [primary, secondary] {
            window.currentSpaceId = space.id
            window.currentTabId = source.id
        }
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
            source,
            role: .spacePinned,
            profileId: nil,
            spaceId: space.id,
            folderId: nil,
            at: 0,
            preferredWindowId: secondary.id
        )

        let insertedForeign = try XCTUnwrap(foreign)
        XCTAssertNil(pin)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(
                for: insertedForeign.id
            ),
            insertedForeign
        )
        XCTAssertFalse(
            tabManager.regularTabCollectionOwner.containsIdentical(
                source,
                in: space.id
            )
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).count,
            1
        )
        let quarantinedResidences = tabManager.transientTabRegistryOwner
            .transientShortcutTabs
        XCTAssertEqual(quarantinedResidences.count, 2)
        XCTAssertTrue(quarantinedResidences.contains { $0 === source })
        XCTAssertTrue(quarantinedResidences.contains {
            $0.id == insertedForeign.id && $0 !== insertedForeign
        })
        XCTAssertFalse(quarantinedResidences.contains {
            $0 === insertedForeign
        })
        _ = cancellable
    }

    private enum DisplayedForeignABATarget {
        case source, fresh
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

    func testPreparedConversionRejectsUnsettledProfileWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://unsettled-profile.example",
            in: space,
            activate: false
        )
        let preparation = tabManager.regularTabShortcutConversion.prepare(tab)
        let intent = tab.profileAssignment.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: tab.url,
            navigationRevision: tab.mainFrameLoads.currentIntent.revision,
            requiresStructuralPersistence: false
        )
        let sourceSpaceID = tab.spaceId

        let converted = tabManager.regularTabShortcutConversion.commit(
            tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(converted)
        XCTAssertTrue(tab.profileAssignment.isCurrent(intent))
        XCTAssertEqual(tab.spaceId, sourceSpaceID)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        tab.profileAssignment.abort(intent)
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
                committedRetirementIsExact: { _ in true },
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
        let profile = Profile(name: "Runtime")
        let states = [first.id: first, second.id: second]
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in first.id }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
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
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: second.id,
            sourceGroup: sourceGroup,
            targetGroup: targetGroup,
            committedTargetGroupID: replacementTarget.id,
            movingMemberID: .regularTab(source.id),
            activatedMemberID: prepared.member.memberID,
            replacementGroups: replacement
        )
        let presentation = makePresentationPreparation(
            effect,
            sourceGroups: prepared.expectedSplitGroups,
            replacementGroups: replacement,
            requiredWindow: second,
            windows: [first, second],
            tabManager: tabManager
        )
        let acceptance = try XCTUnwrap(
            tabManager.regularTabShortcutConversion
                .commitShortcutSidebarDrop(
                    prepared,
                    replacingSplitGroupsWith: replacement,
                    sidebarMutation: .noChange,
                    presentation: presentation
                )
        )

        XCTAssertEqual(acceptance.pinID, prepared.candidatePin.id)
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
                tabManager.liveShortcutTabs.tab(
                    for: acceptance.pinID,
                    in: state.id
                )
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
        let requiredWindow = BrowserWindowState()
        requiredWindow.tabManager = tabManager
        requiredWindow.currentSpaceId = space.id
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: requiredWindow.id,
            sourceGroup: nil,
            targetGroup: target,
            committedTargetGroupID: replacementTarget.id,
            movingMemberID: .regularTab(source.id),
            activatedMemberID: prepared.member.memberID,
            replacementGroups: replacement
        )
        let presentation = makePresentationPreparation(
            effect,
            sourceGroups: prepared.expectedSplitGroups,
            replacementGroups: replacement,
            requiredWindow: requiredWindow,
            windows: [requiredWindow],
            tabManager: tabManager
        )
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
                    sidebarMutation: .noChange,
                    presentation: presentation
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

    func makePresentationPreparation(
        _ effect: SplitDropCommitEffect,
        sourceGroups: [SplitGroup],
        replacementGroups: [SplitGroup],
        requiredWindow: BrowserWindowState,
        windows: [BrowserWindowState],
        tabManager: TabManager
    ) -> RegularTabShortcutSplitPresentationPreparation {
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { tabManager },
            windows: { windows },
            selectTabWithoutPersistence: { tab, window in
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: window,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            },
            publishPreparedSelectionEffects: { _, _, _, _ in },
            publishWindowChange: { _ in },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
        )
        return RegularTabShortcutSplitPresentationPreparation(
            presentations: presentations,
            effect: effect,
            sourceGroups: sourceGroups,
            replacementGroups: replacementGroups,
            requiredWindow: requiredWindow
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

private final class ConversionLifecycleCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private final class ConversionPublicationOrderOracle: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ value: String) { lock.withLock { values.append(value) } }
    var events: [String] { lock.withLock { values } }
}

private final class MainActorTestAction: @unchecked Sendable {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func call() {
        MainActor.assumeIsolated { action() }
    }
}
