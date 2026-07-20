import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitInsertionServiceTests: XCTestCase {
    func testCommandTargetIntentMatchesMembership() {
        let memberID = SplitMemberID.regularTab(UUID())

        XCTAssertEqual(
            SplitInsertionTargetResolver.target(
                memberID: memberID,
                side: .right,
                memberIsGrouped: false
            ).intent,
            .firstSplit
        )
        XCTAssertEqual(
            SplitInsertionTargetResolver.target(
                memberID: memberID,
                side: .right,
                memberIsGrouped: true
            ).intent,
            .siblingEdge
        )
    }

    func testEnterSplitCreatesTwoMemberGroupAndActivatesIncomingTab() throws {
        let fixture = try makeFixture()

        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )
        XCTAssertEqual(
            group.memberIDs,
            [
                .regularTab(fixture.currentTab.id),
                .regularTab(fixture.incomingTab.id),
            ]
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(fixture.incomingTab.id)
            )
        )
    }

    func testEnterSplitAddsThirdMemberToExistingGroup() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )
        let originalGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )
        let thirdTab = fixture.manager.regularTabLifecycleOwner.createNewTab(
            url: "https://third.example",
            in: fixture.space,
            activate: false
        )

        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: thirdTab,
                side: .bottom,
                in: fixture.window
            )
        )

        let committedGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: originalGroup.id)
        )
        XCTAssertEqual(committedGroup.id, originalGroup.id)
        XCTAssertEqual(
            Set(committedGroup.memberIDs),
            Set([
                .regularTab(fixture.currentTab.id),
                .regularTab(fixture.incomingTab.id),
                .regularTab(thirdTab.id),
            ])
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: originalGroup.id,
                activeMemberID: .regularTab(thirdTab.id)
            )
        )
        guard case .split(let axis, _, let children) =
            committedGroup.layoutTree
        else {
            return XCTFail("Expected a pane-relative split insertion")
        }
        XCTAssertEqual(axis, .row)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].memberIDs, [.regularTab(fixture.currentTab.id)])
        XCTAssertEqual(
            children[1].memberIDs,
            [
                .regularTab(fixture.incomingTab.id),
                .regularTab(thirdTab.id),
            ]
        )
    }

    func testEmptySplitCreationSplitsActivePaneInsideExistingGroup() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(
            fixture.insertion.enterSplit(
                with: fixture.incomingTab,
                side: .right,
                in: fixture.window
            )
        )
        let originalGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.currentTab.id)
            )
        )

        XCTAssertTrue(
            fixture.emptyPlaceholders.create(
                side: .bottom,
                in: fixture.window
            )
        )

        let committedGroup = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: originalGroup.id)
        )
        let knownMembers: Set<SplitMemberID> = [
            .regularTab(fixture.currentTab.id),
            .regularTab(fixture.incomingTab.id),
        ]
        let placeholderMembers = Set(committedGroup.memberIDs)
            .subtracting(knownMembers)
        XCTAssertEqual(placeholderMembers.count, 1)
        let placeholderMember = try XCTUnwrap(placeholderMembers.first)
        XCTAssertEqual(committedGroup.memberIDs.count, 3)
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: originalGroup.id,
                activeMemberID: placeholderMember
            )
        )
        guard case .split(let outerAxis, _, let outerChildren) =
            committedGroup.layoutTree else {
            return XCTFail("Expected the original horizontal split root")
        }
        XCTAssertEqual(outerAxis, .row)
        XCTAssertEqual(outerChildren.count, 2)
        XCTAssertEqual(
            outerChildren[0].memberIDs,
            [.regularTab(fixture.currentTab.id)]
        )
        guard case .split(let innerAxis, _, let innerChildren) =
            outerChildren[1] else {
            return XCTFail("Expected a pane-relative nested split")
        }
        XCTAssertEqual(innerAxis, .column)
        XCTAssertEqual(
            innerChildren.map(\.memberIDs),
            [
                [.regularTab(fixture.incomingTab.id)],
                [placeholderMember],
            ]
        )
    }

    func testEmptySplitCreationDoesNotAdoptOrDiscardSameIDReplacement() throws {
        let fixture = try makeFixture()
        var didReplace = false
        var replacement: Tab?
        let cancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                guard !didReplace,
                      let placeholder = fixture.manager
                      .regularTabCollectionOwner.tabs(in: fixture.space.id)
                      .first(where: {
                          $0 !== fixture.currentTab
                              && $0 !== fixture.incomingTab
                      }) else { return }
                didReplace = true
                let sameIDReplacement = Tab(
                    id: placeholder.id,
                    url: placeholder.url,
                    name: placeholder.name,
                    spaceId: placeholder.spaceId,
                    index: placeholder.index,
                    loadsCachedFaviconOnInit: false
                )
                replacement = sameIDReplacement
                let tabs = fixture.manager.regularTabCollectionOwner
                    .tabs(in: fixture.space.id).map {
                        $0 === placeholder ? sameIDReplacement : $0
                    }
                fixture.manager.structuralCollectionMutationOwner.setTabs(
                    tabs,
                    for: fixture.space.id
                )
            }

        XCTAssertFalse(fixture.emptyPlaceholders.create(
            side: .right,
            in: fixture.window
        ))

        let exactReplacement = try XCTUnwrap(replacement)
        XCTAssertTrue(
            fixture.manager.regularTabCollectionOwner.tab(
                for: exactReplacement.id
            ) === exactReplacement
        )
        XCTAssertNil(fixture.manager.splitGroupStore.group(
            containing: .regularTab(fixture.currentTab.id)
        ))
        XCTAssertFalse(fixture.emptyPlaceholders.cancel(in: fixture.window))
        _ = cancellable
    }

    func testFailedEmptySplitRetiresBeforeSameIDRemovalObserverRuns() throws {
        let fixture = try makeFixture()
        var placeholder: Tab?
        var replacement: Tab?
        let cancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                if placeholder == nil {
                    placeholder = fixture.manager.regularTabCollectionOwner
                        .tabs(in: fixture.space.id).first(where: {
                            $0 !== fixture.currentTab
                                && $0 !== fixture.incomingTab
                        })
                    if placeholder != nil {
                        fixture.window.currentTabId = fixture.incomingTab.id
                    }
                    return
                }
                guard replacement == nil, let placeholder,
                      fixture.manager.regularTabCollectionOwner.tab(
                          for: placeholder.id
                      ) == nil else { return }
                let sameIDReplacement = Tab(
                    id: placeholder.id,
                    url: URL(string: "https://replacement.example")!,
                    spaceId: fixture.space.id,
                    index: placeholder.index,
                    loadsCachedFaviconOnInit: false
                )
                replacement = sameIDReplacement
                fixture.manager.structuralCollectionMutationOwner.setTabs(
                    fixture.manager.regularTabCollectionOwner
                        .tabs(in: fixture.space.id) + [sameIDReplacement],
                    for: fixture.space.id
                )
            }

        XCTAssertFalse(fixture.emptyPlaceholders.create(
            side: .right,
            in: fixture.window
        ))

        let exactReplacement = try XCTUnwrap(replacement)
        XCTAssertTrue(
            fixture.manager.regularTabCollectionOwner.tab(
                for: exactReplacement.id
            ) === exactReplacement
        )
        XCTAssertTrue(
            fixture.manager.tabCollectionMembershipOwner.tab(
                for: exactReplacement.id
            ) === exactReplacement
        )
        _ = cancellable
    }

    func testEmptySplitCancelRetiresBeforeSameIDRemovalObserverRuns() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.emptyPlaceholders.create(
            side: .right,
            in: fixture.window
        ))
        let placeholder = try XCTUnwrap(
            fixture.manager.regularTabCollectionOwner
                .tabs(in: fixture.space.id).first(where: {
                    $0 !== fixture.currentTab && $0 !== fixture.incomingTab
                })
        )
        var replacement: Tab?
        let cancellable = fixture.splitUpdates
            .updates(for: fixture.window.id).sink {
                guard replacement == nil,
                      fixture.manager.regularTabCollectionOwner.tab(
                          for: placeholder.id
                      ) == nil else { return }
                let sameIDReplacement = Tab(
                    id: placeholder.id,
                    url: URL(string: "https://replacement.example")!,
                    spaceId: fixture.space.id,
                    index: placeholder.index,
                    loadsCachedFaviconOnInit: false
                )
                replacement = sameIDReplacement
                fixture.manager.structuralCollectionMutationOwner.setTabs(
                    fixture.manager.regularTabCollectionOwner
                        .tabs(in: fixture.space.id) + [sameIDReplacement],
                    for: fixture.space.id
                )
                fixture.window.currentSpaceId = fixture.space.id
                fixture.window.currentTabId = sameIDReplacement.id
                fixture.window.selectionHistory
                    .recentRegularTabIdsBySpace[fixture.space.id] = [
                        sameIDReplacement.id,
                    ]
            }

        XCTAssertTrue(fixture.emptyPlaceholders.cancel(in: fixture.window))

        let exactReplacement = try XCTUnwrap(replacement)
        XCTAssertTrue(
            fixture.manager.regularTabCollectionOwner.tab(
                for: exactReplacement.id
            ) === exactReplacement
        )
        XCTAssertTrue(
            fixture.manager.tabCollectionMembershipOwner.tab(
                for: exactReplacement.id
            ) === exactReplacement
        )
        XCTAssertEqual(
            fixture.window.selectionHistory
                .recentRegularTabIdsBySpace[fixture.space.id],
            [exactReplacement.id]
        )
        XCTAssertEqual(fixture.window.currentTabId, exactReplacement.id)
        XCTAssertFalse(fixture.emptyPlaceholders.cancel(in: fixture.window))
        _ = cancellable
    }

    func testEmptySplitReplacementRelocatesShortcutBeforeSettlingPlaceholder() throws {
        let scenario = try makeShortcutPlaceholderFixture()
        let fixture = scenario.fixture

        XCTAssertTrue(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))

        let groupAfter = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: scenario.group.id)
        )
        XCTAssertTrue(groupAfter.contains(.shortcutPin(scenario.pin.id)))
        XCTAssertFalse(groupAfter.contains(
            .regularTab(scenario.placeholderTabID)
        ))
        XCTAssertNil(
            fixture.manager.tabCollectionMembershipOwner.tab(
                for: scenario.placeholderTabID
            )
        )
        XCTAssertEqual(
            fixture.manager.liveShortcutTabs.entry(containing: scenario.liveTab)?
                .presentationPage,
            LiveShortcutPresentationPageReceipt(
                windowID: fixture.window.id,
                spaceID: scenario.targetSpace.id,
                profileID: scenario.profileID
            )
        )
        XCTAssertFalse(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))
    }

    func testEmptySplitWindowUpdateSeesTerminalModelAndPreservesReentrantMutation()
        throws {
        let scenario = try makeShortcutPlaceholderFixture()
        let fixture = scenario.fixture
        let targetPage = LiveShortcutPresentationPageReceipt(
            windowID: fixture.window.id,
            spaceID: scenario.targetSpace.id,
            profileID: scenario.profileID
        )
        let placeholder = try XCTUnwrap(
            fixture.manager.tabCollectionMembershipOwner.tab(
                for: scenario.placeholderTabID
            )
        )
        let lifecycle = EmptySplitLifecycleNotificationRecorder(
            tab: placeholder
        )
        var observerInvocationCount = 0
        var firstObservedResidence: LiveShortcutPresentationPageReceipt?
        var firstObservedGroup: SplitGroup?
        var firstObservedPlaceholder: Tab?
        var firstObservedSelection: WindowSplitSelection?
        var reentrantRetryAccepted: Bool?
        var observerMutationAccepted = false
        var structuralEvents = 0
        let structureCancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        var didReenter = false
        let updateCancellable = fixture.splitUpdates
            .updates(for: fixture.window.id).sink {
                observerInvocationCount += 1
                guard didReenter == false else { return }
                didReenter = true
                firstObservedResidence = fixture.manager.liveShortcutTabs
                    .entry(containing: scenario.liveTab)?.presentationPage
                firstObservedGroup = fixture.manager.splitGroupStore.group(
                    id: scenario.group.id
                )
                firstObservedPlaceholder = fixture.manager
                    .tabCollectionMembershipOwner.tab(
                        for: scenario.placeholderTabID
                    )
                firstObservedSelection = fixture.window.splitSelection

                reentrantRetryAccepted = fixture.emptyPlaceholders.replace(
                    with: scenario.liveTab,
                    in: fixture.window
                )
                let committedGroups = fixture.manager.splitGroupStore.groups
                observerMutationAccepted = fixture.manager.splitGroupMutations
                    .replaceAll(
                        expected: committedGroups,
                        with: [],
                        persist: false
                    )
            }

        XCTAssertTrue(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))

        XCTAssertEqual(observerInvocationCount, 1)
        XCTAssertEqual(firstObservedResidence, targetPage)
        XCTAssertTrue(firstObservedGroup?.contains(
            .shortcutPin(scenario.pin.id)
        ) == true)
        XCTAssertFalse(firstObservedGroup?.contains(
            .regularTab(scenario.placeholderTabID)
        ) == true)
        XCTAssertNil(firstObservedPlaceholder)
        XCTAssertEqual(
            firstObservedSelection,
            WindowSplitSelection(
                groupID: scenario.group.id,
                activeMemberID: .shortcutPin(scenario.pin.id)
            )
        )
        XCTAssertEqual(reentrantRetryAccepted, false)
        XCTAssertTrue(observerMutationAccepted)
        XCTAssertTrue(fixture.manager.splitGroupStore.groups.isEmpty)
        XCTAssertNil(fixture.manager.tabCollectionMembershipOwner.tab(
            for: scenario.placeholderTabID
        ))
        XCTAssertFalse(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertEqual(lifecycle.count, 1)
        withExtendedLifetime((updateCancellable, structureCancellable)) {}
    }

    func testEmptySplitReplacementReleasesExactCompanionLauncherWithoutRebinding() throws {
        let scenario = try makeShortcutPlaceholderFixture()
        let fixture = scenario.fixture
        let companion = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: scenario.profileID,
            index: 1,
            launchURL: URL(string: "https://companion.example")!,
            title: "Companion"
        )
        fixture.manager.shortcutPinCollectionStateOwner
            .replacePinnedByProfile([
                scenario.profileID: [scenario.pin, companion],
            ])
        let companionTab = Tab(loadsCachedFaviconOnInit: false)
        companionTab.bindToShortcutPin(companion)
        companionTab.profileId = scenario.profileID
        XCTAssertTrue(fixture.manager.liveShortcutTabs.register(
            companionTab,
            for: companion.id,
            in: fixture.window.id,
            presentationPage: scenario.sourcePage
        ))
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(scenario.pin.id),
                .shortcutPin(companion.id),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: scenario.sourceSpace.id)
        ))
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [scenario.group],
            with: [scenario.group, sourceGroup],
            persist: false
        ))

        var runtimeWindowPersistenceCount = 0
        var profileExecutionCount = 0
        let profile = Profile(id: scenario.profileID, name: "Profile")
        fixture.runtimeAttachment.detach()
        fixture.runtimeAttachment.attach(
            TestRuntimePorts.make(
                currentProfileId: { scenario.profileID },
                defaultProfileId: { scenario.profileID },
                profileExists: { $0 == scenario.profileID },
                profile: { $0 == profile.id ? profile : nil },
                windowState: {
                    $0 == fixture.window.id ? fixture.window : nil
                },
                windows: { [(fixture.window.id, fixture.window)] },
                windowStates: { [fixture.window] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .rejecting,
                    executeProfileAssignment: { tab, _, intent in
                        profileExecutionCount += 1
                        return tab.profileAssignment.commit(intent)
                            ? .committed
                            : .stale
                    }
                ),
                persistWindowSession: { _ in
                    runtimeWindowPersistenceCount += 1
                }
            )
        )
        let companionEntry = try XCTUnwrap(
            fixture.manager.liveShortcutTabs.entry(containing: companionTab)
        )
        let profileRevision = companionTab.profileAssignment.changeRevision
        var structuralEvents = 0
        let cancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        XCTAssertTrue(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))

        XCTAssertNil(fixture.manager.splitGroupStore.group(id: sourceGroup.id))
        XCTAssertNil(fixture.manager.splitGroupStore.group(
            containing: .shortcutPin(companion.id)
        ))
        XCTAssertIdentical(
            fixture.manager.shortcutPinCollectionStateOwner
                .shortcutPin(by: companion.id),
            companion
        )
        XCTAssertTrue(
            fixture.manager.liveShortcutTabs.entry(containing: companionTab)?
                .isIdentical(to: companionEntry) == true
        )
        XCTAssertEqual(
            companionTab.profileAssignment.changeRevision,
            profileRevision
        )
        XCTAssertFalse(companionTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(profileExecutionCount, 0)
        XCTAssertEqual(runtimeWindowPersistenceCount, 0)
        XCTAssertEqual(structuralEvents, 1)
        _ = cancellable
    }

    func testLateShortcutDriftRollsBackStagedPlaceholderWithoutEffects() throws {
        let scenario = try makeShortcutPlaceholderFixture()
        let fixture = scenario.fixture
        var events = 0
        let cancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { events += 1 }
        events = 0
        let revision = fixture.manager.structuralLookupCoordinator
            .mutationRevision
        let dirtySet = fixture.manager.structuralPersistence.dirtySet
        let persistenceSchedulingRevision = fixture.manager
            .structuralPersistence.schedulingRevision
        let currentTabID = fixture.window.currentTabId
        let currentSpaceID = fixture.window.currentSpaceId
        let currentShortcutPinID = fixture.window.currentShortcutPinId
        let currentShortcutPinRole = fixture.window.currentShortcutPinRole
        let splitSelection = fixture.window.splitSelection

        let accepted = fixture.manager.shortcutPresentationActivation
            .commitActivation(
                scenario.liveTab,
                in: fixture.window.id,
                presentationSpaceID: scenario.targetSpace.id
            ) { admitted in
                guard let terminal = fixture.emptyPlaceholders
                    .prepareReplacementCommit(
                        with: admitted,
                        in: fixture.window
                    ) else { return nil }
                scenario.pin.title = "Drifted"
                return terminal
            }

        XCTAssertFalse(accepted)
        XCTAssertEqual(fixture.manager.splitGroupStore.groups, [scenario.group])
        XCTAssertNotNil(
            fixture.manager.tabCollectionMembershipOwner.tab(
                for: scenario.placeholderTabID
            )
        )
        XCTAssertEqual(
            fixture.manager.liveShortcutTabs.entry(containing: scenario.liveTab)?
                .presentationPage,
            scenario.sourcePage
        )
        XCTAssertEqual(events, 0)
        XCTAssertEqual(
            fixture.manager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        XCTAssertEqual(
            fixture.manager.structuralPersistence.dirtySet,
            dirtySet
        )
        XCTAssertEqual(
            fixture.manager.structuralPersistence.schedulingRevision,
            persistenceSchedulingRevision
        )
        XCTAssertEqual(fixture.window.currentTabId, currentTabID)
        XCTAssertEqual(fixture.window.currentSpaceId, currentSpaceID)
        XCTAssertEqual(
            fixture.window.currentShortcutPinId,
            currentShortcutPinID
        )
        XCTAssertEqual(
            fixture.window.currentShortcutPinRole,
            currentShortcutPinRole
        )
        XCTAssertEqual(fixture.window.splitSelection, splitSelection)

        scenario.pin.title = "Essential"
        XCTAssertTrue(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))
        _ = cancellable
    }
}

private final class EmptySplitLifecycleNotificationRecorder:
    @unchecked Sendable {
    private let lock = NSLock()
    private var notificationCount = 0
    private var observer: NSObjectProtocol?

    @MainActor
    init(tab: Tab) {
        observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: tab,
            queue: nil
        ) { [weak self] _ in
            self?.lock.withLock {
                self?.notificationCount += 1
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var count: Int {
        lock.withLock { notificationCount }
    }
}

@MainActor
private extension SplitInsertionServiceTests {
    struct Fixture {
        let manager: BrowserManager
        let runtimeAttachment: TabRuntimePortConnection
        let window: BrowserWindowState
        let space: Space
        let currentTab: Tab
        let incomingTab: Tab
        let insertion: SplitInsertionService
        let emptyPlaceholders: EmptySplitService
        let splitUpdates: SplitWindowUpdateStream
    }

    struct ShortcutPlaceholderFixture {
        let fixture: Fixture
        let profileID: UUID
        let sourceSpace: Space
        let targetSpace: Space
        let group: SplitGroup
        let placeholderTabID: UUID
        let pin: ShortcutPin
        let liveTab: Tab
        let sourcePage: LiveShortcutPresentationPageReceipt
    }

    func makeFixture() throws -> Fixture {
        let window = BrowserWindowState()
        let manager = BrowserManager()
        manager.runtimePortConnection.attach(TestRuntimePorts.make(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id }
            )
        ))
        let runtimeAttachment = manager.runtimePortConnection
        manager.windowRegistry.register(window)
        let space = try XCTUnwrap(manager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
        let currentTab = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://current.example",
            in: space,
            activate: true
        )
        let incomingTab = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://incoming.example",
            in: space,
            activate: false
        )
        window.currentSpaceId = space.id
        window.currentTabId = currentTab.id

        let currentTabInWindow: @MainActor (BrowserWindowState) -> Tab? = {
            state in
            state.currentTabId.flatMap {
                manager.tabCollectionMembershipOwner.tab(for: $0)
            }
        }
        let members = makeTestSplitRuntimeMemberResolver(manager)
        let presentations = makeTestWindowSplitPresentationSynchronizer(
            browser: manager,
            windows: { [window] }
        )
        let windowRegistry = WindowRegistry()
        windowRegistry.register(window)
        let query = WindowSplitQuery(
            splitGroups: manager.splitGroupStore,
            regularTabs: manager.regularTabCollectionOwner,
            pins: manager.shortcutPinCollectionStateOwner,
            liveShortcuts: manager.liveShortcutTabs,
            windows: windowRegistry,
            previewIsActive: { _ in false }
        )
        let dropTargets = SplitDropTargetService(
            splitGroups: manager.splitGroupStore,
            windowState: { $0 == window.id ? window : nil },
            currentTab: currentTabInWindow,
            query: query,
            memberResolver: members
        )
        let layout = SplitLayoutService(
            topology: SplitLayoutTopologyTransaction(
                splitGroups: manager.splitGroupStore,
                mutations: manager.splitGroupMutations,
                regularTabs: manager.regularTabCollectionOwner
            ),
            query: query,
            weightMutations: SplitLayoutWeightMutationService(
                splitGroups: manager.splitGroupStore,
                persistence: manager.structuralPersistence
            ),
            presentations: presentations,
            dissolution: SplitGroupDissolutionService(
                splitGroups: manager.splitGroupStore,
                mutations: manager.splitGroupMutations,
                presentations: presentations
            )
        )
        let tabClosures = SplitTabClosureService(
            dropTargets: dropTargets,
            layout: layout
        )
        let placeholderRetirement = EmptySplitPlaceholderRetirementService(
            regularTabs: manager.regularTabCollectionOwner,
            structuralLookup: manager.structuralLookupCoordinator,
            persistence: manager.structuralPersistence,
            runtimeConnection: manager.runtimePortConnection,
            runtimeCleanup: RegularTabClosureRuntimeCleanup(
                membership: manager.tabCollectionMembershipOwner
            )
        )
        let placeholderReplacements = SplitPlaceholderReplacementPlanner(
            query: SplitPlaceholderReplacementQuery(
                regularTabs: manager.regularTabCollectionOwner,
                splitGroups: manager.splitGroupStore,
                membership: manager.splitGroupMembership,
                liveShortcuts: manager.liveShortcutTabs,
                members: members
            ),
            launcherRelease: ShortcutSplitLauncherReleasePlanner(
                pins: manager.shortcutPinCollectionStateOwner,
                destinationResolver:
                    makeTestShortcutSplitLauncherDestinationResolver(manager)
            ),
            splitMutations: manager.splitGroupMutations,
            retirement: placeholderRetirement,
            presentations: presentations
        )
        let drops = SplitDropService(
            topology: SplitDropTopologyTransaction(
                structuralLookup: manager.structuralLookupCoordinator,
                membership: manager.splitGroupMembership,
                splitGroups: manager.splitGroupStore,
                mutations: manager.splitGroupMutations
            ),
            memberResolver: members,
            regularShortcutSidebarDrop:
                RegularTabShortcutSidebarDropTransaction(
                    conversion: manager.regularTabShortcutConversion,
                    presentations: presentations
                ),
            shortcutMemberRelocation:
                manager.splitGroupShortcutMemberRelocation,
            duplication: makeTestSplitTabDuplicationService(manager),
            presentations: presentations,
            notifyLimit: { _ in }
        )
        let insertion = SplitInsertionService(
            currentTab: currentTabInWindow,
            memberIsGrouped: {
                manager.splitGroupStore.group(containing: $0) != nil
            },
            members: members,
            drops: drops
        )
        let emptySplitSession = EmptySplitSession(
            structuralTransactions: manager.structuralLookupCoordinator,
            terminalMutations: manager.structuralCollectionMutationOwner,
            placeholderRetirement: placeholderRetirement
        )
        let emptyPlaceholders = EmptySplitService(
            placeholders: EmptySplitPlaceholderFactory(
                spaces: manager.spaceStateOwner,
                regularTabs: manager.regularTabLifecycleOwner,
                retirement: placeholderRetirement,
                structuralTransactions: manager.structuralLookupCoordinator,
                terminalMutations: manager.structuralCollectionMutationOwner
            ),
            insertion: insertion,
            activations: manager.shortcutPresentationActivation,
            session: emptySplitSession,
            replacements: EmptySplitReplacementService(
                replacements: placeholderReplacements,
                session: emptySplitSession,
                terminalMutations: manager.structuralCollectionMutationOwner
            )
        )
        runtimeAttachment.detach()
        runtimeAttachment.attach(TestRuntimePorts.make(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id }
            ),
            splitCoordination: LiveTabSplitCoordinationPort(
                tabClosures: tabClosures,
                query: query
            )
        ))
        return Fixture(
            manager: manager,
            runtimeAttachment: runtimeAttachment,
            window: window,
            space: space,
            currentTab: currentTab,
            incomingTab: incomingTab,
            insertion: insertion,
            emptyPlaceholders: emptyPlaceholders,
            splitUpdates: manager.splitUpdateChannel.stream
        )
    }

    func makeShortcutPlaceholderFixture() throws
        -> ShortcutPlaceholderFixture {
        let fixture = try makeFixture()
        let profileID = UUID()
        let sourceSpace = try XCTUnwrap(fixture.manager.sidebarSpaceLifecycle.createSpace(
            name: "Source",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profileID
        ))
        let targetSpace = try XCTUnwrap(fixture.manager.sidebarSpaceLifecycle.createSpace(
            name: "Target",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profileID
        ))
        let targetRegularTab = fixture.manager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://target.example",
                in: targetSpace,
                activate: false
            )
        fixture.window.currentSpaceId = targetSpace.id
        fixture.window.currentTabId = targetRegularTab.id
        XCTAssertTrue(fixture.emptyPlaceholders.create(
            side: .right,
            in: fixture.window
        ))
        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(targetRegularTab.id)
            )
        )
        let placeholderTabID = try XCTUnwrap(
            group.memberIDs.compactMap { memberID -> UUID? in
                guard case .regularTab(let tabID) = memberID,
                      tabID != targetRegularTab.id else { return nil }
                return tabID
            }.first
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        fixture.manager.shortcutPinCollectionStateOwner
            .replacePinnedByProfile([profileID: [pin]])
        let liveTab = Tab(loadsCachedFaviconOnInit: false)
        liveTab.bindToShortcutPin(pin)
        liveTab.profileId = profileID
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: fixture.window.id,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(fixture.manager.liveShortcutTabs.register(
            liveTab,
            for: pin.id,
            in: fixture.window.id,
            presentationPage: sourcePage
        ))
        return ShortcutPlaceholderFixture(
            fixture: fixture,
            profileID: profileID,
            sourceSpace: sourceSpace,
            targetSpace: targetSpace,
            group: group,
            placeholderTabID: placeholderTabID,
            pin: pin,
            liveTab: liveTab,
            sourcePage: sourcePage
        )
    }
}
