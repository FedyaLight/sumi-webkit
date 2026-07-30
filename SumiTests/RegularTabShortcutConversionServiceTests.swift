import Combine
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class RegularTabShortcutConversionServiceTests: XCTestCase {
    func testNilRuntimeDetachedConversionCommitsTerminalModelExactlyOnce() throws {
        let fixture = makeNilRuntimeFixture()
        let lifecycleEvents = ConversionLifecycleCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: fixture.input.tab,
            queue: nil
        ) { _ in lifecycleEvents.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var structuralEvents = 0
        let cancellable = fixture.events
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = try XCTUnwrap(
            fixture.conversion.convert(
                fixture.input.tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: fixture.input.space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                )
            )
        )

        XCTAssertEqual(lifecycleEvents.count, 1)
        XCTAssertEqual(structuralEvents, 1)
        let state = fixture.state(pin)
        XCTAssertNil(state.residentTab)
        XCTAssertFalse(state.containsRegularTab)
        XCTAssertIdentical(state.pin, pin)
        _ = cancellable
    }

    func testDetachedConversionRejectsSameIDMembershipDrift() throws {
        let fixture = makeMembershipDriftFixture()
        let preparation = fixture.conversion.prepare(fixture.input.source)
        fixture.attachReplacement()

        let acceptance = fixture.conversion.commit(
            fixture.input.source,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: fixture.input.space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(acceptance)
        let state = fixture.state()
        XCTAssertIdentical(state.residentTab, fixture.input.replacement)
        XCTAssertTrue(state.containsSource)
        XCTAssertTrue(state.pinsAreEmpty)
    }

    func testDetachedConversionRejectsRuntimeAttachmentDriftBeforeClaim()
        throws {
        let repository = WebViewSessionRepository()
        var canRetireCalls = 0
        var destroyCalls = 0
        var persistedWindowIDs: [UUID] = []
        let profile = Profile(name: "Runtime")
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
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: lifecycle,
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        let container = try makeInMemoryStartupDatabase()
        let tabManager = BrowserManager(
            webViewSessions: repository,
            windowRegistry: WindowRegistry(),
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            dataServices: .unavailable(),
            initialTabRuntimePorts: runtimeA
        )
        let space = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Space",
            profileID: profile.id
        )
        let webView = WKWebView()
        let source = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tabManager.regularTabCollectionOwner.insert(source, in: space.id, at: 0)
        let preparation = tabManager.regularTabShortcutConversion.prepare(source)
        tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(
            TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
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
        let profile = Profile(name: "Runtime")
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            ),
            notifyTabClosedIfLoaded: { _ in order.record("physical") }
        )
        let container = try makeInMemoryStartupDatabase()
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            runtimePorts: runtime
        )
        let space = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Space",
            profileID: profile.id
        )
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
        let profile = Profile(name: "Runtime")
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
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: lifecycle,
            notifyTabClosedIfLoaded: { _ in order.record("extension") },
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        let container = try makeInMemoryStartupDatabase()
        let tabManager = BrowserManager(
            webViewSessions: repository,
            windowRegistry: WindowRegistry(),
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            dataServices: .unavailable(),
            initialTabRuntimePorts: runtime
        )
        let space = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Space",
            profileID: profile.id
        )
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
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { nil },
            defaultProfileId: { fallbackProfile.id },
            profile: { $0 == fallbackProfile.id ? fallbackProfile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id }
            )
        ))
        let space = Space(name: "Space")
        tabManager.spaceStateOwner.append(space)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://profileless-conversion.example",
            in: space,
            activate: false
        )
        window.currentSpaceId = space.id
        window.currentTabId = tab.id

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
                ),
                preferredWindowId: window.id
            )
        )

        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: window.id),
            tab
        )
    }

    func testRegularSplitMemberConversionRejectsWithoutPartialMutation()
        throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [first.id: first, second.id: second]
        var visibleIds: [UUID] = []
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in first.id }
            ),
            visibleSplitTabIds: { _ in visibleIds }
        ))
        let space = Space(
            name: "Space",
            profileId: profile.id
        )
        tabManager.spaceStateOwner.append(space)
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

        XCTAssertNil(
            tabManager.regularTabShortcutConversion.convert(
                source,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                ),
                preferredWindowId: second.id
            ),
            "A regular split cannot become a mixed regular/shortcut group"
        )

        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            group
        )
        XCTAssertEqual(
            first.splitSelection?.activeMemberID,
            .regularTab(source.id)
        )
        XCTAssertEqual(
            second.splitSelection?.activeMemberID,
            .regularTab(source.id)
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
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
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                materializeVisibleTabWebViewIfNeeded: { tab, window in
                    eventsSeenAtMaterialization.append(structuralEvents)
                    materialized.append((tab.id, window.id))
                },
                primaryTrackedWindowId: { tabID in
                    primary.currentTabId == tabID ? primary.id : nil
                }
            )
        ))
        let space = Space(
            name: "Space",
            profileId: profile.id
        )
        tabManager.spaceStateOwner.append(space)
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
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                ),
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
        let originalRuntime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                materializeVisibleTabWebViewIfNeeded: { tab, _ in
                    originalMaterializations.append(tab.id)
                },
                primaryTrackedWindowId: { _ in primary.id }
            )
        )
        let tabManager = BrowserManager(runtimePorts: originalRuntime)
        let space = Space(
            name: "Space",
            profileId: profile.id
        )
        tabManager.spaceStateOwner.append(space)
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
                tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(
                    replacementRuntime
                )
            }

        let pin = tabManager.regularTabShortcutConversion.convert(
            source,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            ),
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

    func assertDisplayedForeignABA(
        target: DisplayedForeignABATarget
    ) throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [primary.id: primary, secondary.id: secondary]
        var tabManager: BrowserManager!
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
                    replaced = tabManager.liveShortcutTabs.snapshot.values
                        .lazy.flatMap(\.values).first { $0 !== source }
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
        let container = try makeInMemoryStartupDatabase()
        tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            runtimePorts: runtime
        )
        let space = installTestSpace(
            in: tabManager.spaceStateOwner,
            name: "Space",
            profileID: profile.id
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

        let pin = tabManager.regularTabShortcutConversion.convert(
            source,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            ),
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
        let quarantinedResidences = tabManager.liveShortcutTabs.snapshot
            .values.flatMap(\.values)
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

    enum DisplayedForeignABATarget {
        case source, fresh
    }

    func testSplitVisibleInAnotherWindowRejectsConversionWithoutPartialMutation() throws {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [selected.id: selected, splitOnly.id: splitOnly]
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnly.id ? [selected.currentTabId].compactMap(\.self) : []
            }
        ))
        let space = Space(name: "Space", profileId: profile.id)
        tabManager.spaceStateOwner.append(space)
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
            tabManager.regularTabShortcutConversion.convert(
                original,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                ),
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
        let profile = Profile(name: "Runtime")
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in primaryWindowId }
            ),
            persistWindowSession: { persistedWindowIds.append($0.id) }
        ))
        let space = Space(name: "Space", profileId: profile.id)
        tabManager.spaceStateOwner.append(space)
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
        let fixture = try makeForeignPlanFixture()
        let preparation = fixture.conversion
            .prepare(
                fixture.input.source,
                preferredWindowId: fixture.input.window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid displayed conversion plan")
        }
        let windowSession = ShortcutConversionWindowSessionState(
            fixture.input.window
        )
        var structuralEvents = 0
        let cancellable = fixture.events
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let converted = fixture.conversion
            .commit(
                fixture.input.other,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: fixture.input.space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        let state = fixture.state()
        XCTAssertTrue(state.persistedWindowIDs.isEmpty)
        XCTAssertTrue(state.containsSource)
        XCTAssertTrue(state.containsOther)
        XCTAssertFalse(fixture.input.source.isShortcutLiveInstance)
        XCTAssertFalse(fixture.input.other.isShortcutLiveInstance)
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(fixture.input.window),
            windowSession
        )
        _ = cancellable
    }

    func testNoDisplayingWindowPreparesDetachedConversionWithoutMutation() throws {
        let fixture = makeHiddenConversionFixture()
        let preparation = fixture.conversion.prepare(fixture.input.tab)

        guard case .detached(let plan) = preparation else {
            return XCTFail("Expected a detached conversion plan")
        }
        XCTAssertEqual(plan.sourceTabId, fixture.input.tab.id)
        let state = fixture.state()
        XCTAssertTrue(state.containsTab)
        XCTAssertFalse(fixture.input.tab.isShortcutLiveInstance)
        XCTAssertTrue(state.liveTabsAreEmpty)
    }

    func testPreparedConversionRejectsUnsettledProfileWithoutMutation() throws {
        let fixture = makeUnsettledProfileFixture()
        let preparation = fixture.conversion.prepare(fixture.input.tab)
        let intent = fixture.input.tab.profileAssignment.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: fixture.input.tab.url,
            navigationRevision: fixture.input.tab.mainFrameLoads.currentIntent.revision,
            requiresStructuralPersistence: false
        )
        let sourceSpaceID = fixture.input.tab.spaceId

        let converted = fixture.conversion.commit(
            fixture.input.tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: fixture.input.space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(converted)
        XCTAssertTrue(fixture.input.tab.profileAssignment.isCurrent(intent))
        XCTAssertEqual(fixture.input.tab.spaceId, sourceSpaceID)
        let state = fixture.state()
        XCTAssertTrue(state.containsTab)
        XCTAssertTrue(state.liveTabsAreEmpty)
        XCTAssertTrue(state.pinsAreEmpty)
        fixture.input.tab.profileAssignment.abort(intent)
    }

    func makeNilRuntimeFixture() -> NilRuntimeConversionFixture {
        let browser = BrowserManager()
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://nil-runtime-conversion.example",
            in: space,
            activate: false
        )
        return NilRuntimeConversionFixture(
            input: .init(space: space, tab: tab),
            conversion: browser.regularTabShortcutConversion,
            events: browser.tabStructureEventBus,
            state: { pin in
                .init(
                    residentTab: browser.tabCollectionMembershipOwner
                        .tab(for: tab.id),
                    containsRegularTab: browser.regularTabCollectionOwner
                        .contains(tab),
                    pin: browser.shortcutPinCollectionStateOwner
                        .shortcutPin(by: pin.id)
                )
            }
        )
    }

    func makeMembershipDriftFixture() -> MembershipDriftFixture {
        let browser = BrowserManager()
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let source = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://membership-drift.example/source",
            in: space,
            activate: false
        )
        let replacement = browser.tabFactory.makeTab(
            id: source.id,
            url: URL(string: "https://membership-drift.example/replacement")!,
            loadsCachedFaviconOnInit: false
        )
        return MembershipDriftFixture(
            input: .init(
                space: space,
                source: source,
                replacement: replacement
            ),
            conversion: browser.regularTabShortcutConversion,
            attachReplacement: {
                browser.tabCollectionMembershipOwner.attach(replacement)
            },
            state: {
                .init(
                    residentTab: browser.tabCollectionMembershipOwner
                        .tab(for: source.id),
                    containsSource: browser.regularTabCollectionOwner
                        .contains(source),
                    pinsAreEmpty: browser.shortcutPinCollectionStateOwner
                        .spacePinnedPins(for: space.id).isEmpty
                )
            }
        )
    }

    func makeForeignPlanFixture() throws -> ForeignPlanFixture {
        let window = BrowserWindowState()
        var sourceTabID: UUID?
        var persistedWindowIDs: [UUID] = []
        let profile = Profile(name: "Runtime")
        let browser = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { tabID in
                    tabID == sourceTabID ? window.id : nil
                }
            ),
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        ))
        let space = Space(name: "Space", profileId: profile.id)
        browser.spaceStateOwner.append(space)
        let source = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-source.example",
            in: space,
            activate: false
        )
        let other = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-other.example",
            in: space,
            activate: false
        )
        sourceTabID = source.id
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        return ForeignPlanFixture(
            input: .init(
                window: window,
                space: space,
                source: source,
                other: other
            ),
            conversion: browser.regularTabShortcutConversion,
            events: browser.tabStructureEventBus,
            state: {
                .init(
                    persistedWindowIDs: persistedWindowIDs,
                    containsSource: browser.regularTabCollectionOwner
                        .contains(source),
                    containsOther: browser.regularTabCollectionOwner
                        .contains(other)
                )
            }
        )
    }

    func makeHiddenConversionFixture() -> HiddenConversionFixture {
        let browser = BrowserManager()
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden.example",
            in: space,
            activate: false
        )
        return HiddenConversionFixture(
            input: .init(space: space, tab: tab),
            conversion: browser.regularTabShortcutConversion,
            state: {
                .init(
                    containsTab: browser.regularTabCollectionOwner
                        .contains(tab),
                    liveTabsAreEmpty: browser.liveShortcutTabs.snapshot.isEmpty
                )
            }
        )
    }

    func makeUnsettledProfileFixture() -> UnsettledProfileFixture {
        let browser = BrowserManager()
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://unsettled-profile.example",
            in: space,
            activate: false
        )
        return UnsettledProfileFixture(
            input: .init(space: space, tab: tab),
            conversion: browser.regularTabShortcutConversion,
            state: {
                .init(
                    containsTab: browser.regularTabCollectionOwner
                        .contains(tab),
                    liveTabsAreEmpty: browser.liveShortcutTabs.snapshot.isEmpty,
                    pinsAreEmpty: browser.shortcutPinCollectionStateOwner
                        .spacePinnedPins(for: space.id).isEmpty
                )
            }
        )
    }
}

@MainActor
struct NilRuntimeConversionFixture {
    struct Input {
        let space: Space
        let tab: Tab
    }

    struct State {
        let residentTab: Tab?
        let containsRegularTab: Bool
        let pin: ShortcutPin?
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let events: TabStructureEventBus
    let state: @MainActor (ShortcutPin) -> State
}

@MainActor
struct MembershipDriftFixture {
    struct Input {
        let space: Space
        let source: Tab
        let replacement: Tab
    }

    struct State {
        let residentTab: Tab?
        let containsSource: Bool
        let pinsAreEmpty: Bool
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let attachReplacement: @MainActor () -> Void
    let state: @MainActor () -> State
}

@MainActor
struct ForeignPlanFixture {
    struct Input {
        let window: BrowserWindowState
        let space: Space
        let source: Tab
        let other: Tab
    }

    struct State {
        let persistedWindowIDs: [UUID]
        let containsSource: Bool
        let containsOther: Bool
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let events: TabStructureEventBus
    let state: @MainActor () -> State
}

@MainActor
struct HiddenConversionFixture {
    struct Input {
        let space: Space
        let tab: Tab
    }

    struct State {
        let containsTab: Bool
        let liveTabsAreEmpty: Bool
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let state: @MainActor () -> State
}

@MainActor
struct UnsettledProfileFixture {
    struct Input {
        let space: Space
        let tab: Tab
    }

    struct State {
        let containsTab: Bool
        let liveTabsAreEmpty: Bool
        let pinsAreEmpty: Bool
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let state: @MainActor () -> State
}

final class ConversionLifecycleCounter: @unchecked Sendable {
    let lock = NSLock()
    var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

final class ConversionPublicationOrderOracle: @unchecked Sendable {
    let lock = NSLock()
    var values: [String] = []

    func record(_ value: String) { lock.withLock { values.append(value) } }
    var events: [String] { lock.withLock { values } }
}

final class MainActorTestAction: @unchecked Sendable {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func call() {
        MainActor.assumeIsolated { action() }
    }
}
