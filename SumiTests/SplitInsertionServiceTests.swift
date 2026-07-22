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
                    webViewSessions: fixture.manager.webViewSessions,
                    loadsCachedFaviconOnInit: false
                )
                sameIDReplacement.profileId = placeholder.profileId
                sameIDReplacement.attachBrowserRuntime(
                    TabBrowserRuntimeFactory.make(for: fixture.manager)
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
                    webViewSessions: fixture.manager.webViewSessions,
                    loadsCachedFaviconOnInit: false
                )
                sameIDReplacement.profileId = placeholder.profileId
                sameIDReplacement.attachBrowserRuntime(
                    TabBrowserRuntimeFactory.make(for: fixture.manager)
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
                    webViewSessions: fixture.manager.webViewSessions,
                    loadsCachedFaviconOnInit: false
                )
                sameIDReplacement.profileId = placeholder.profileId
                sameIDReplacement.attachBrowserRuntime(
                    TabBrowserRuntimeFactory.make(for: fixture.manager)
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

    func testEmptyRegularSplitRejectsShortcutReplacementWithoutMutation() throws {
        let scenario = try makeShortcutPlaceholderFixture()
        let fixture = scenario.fixture

        XCTAssertFalse(fixture.emptyPlaceholders.replace(
            with: scenario.liveTab,
            in: fixture.window
        ))
        XCTAssertEqual(fixture.manager.splitGroupStore.groups, [scenario.group])
        XCTAssertNotNil(fixture.manager.tabCollectionMembershipOwner.tab(
            for: scenario.placeholderTabID
        ))
        XCTAssertEqual(
            fixture.manager.liveShortcutTabs.entry(containing: scenario.liveTab)?
                .presentationPage,
            scenario.sourcePage
        )
    }

}

@MainActor
private extension SplitInsertionServiceTests {
    struct Fixture {
        let manager: BrowserManager
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
        let profile = Profile(name: "Split Tests")
        let splitCoordination = LateBoundTabSplitCoordinationPort()
        var runtimeBrowser: BrowserManager?
        let manager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id },
                prepareTab: { tab in
                    guard let runtimeBrowser else { return }
                    tab.attachBrowserRuntime(
                        TabBrowserRuntimeFactory.make(for: runtimeBrowser)
                    )
                }
            ),
            splitCoordination: splitCoordination
        ))
        runtimeBrowser = manager
        manager.profileManager.profiles = [profile]
        manager.currentProfile = profile
        manager.windowRegistry.register(window)
        let space = try XCTUnwrap(manager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let currentTab = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://current.example",
            in: space,
            activate: false
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
        splitCoordination.base = LiveTabSplitCoordinationPort(
            tabClosures: tabClosures,
            query: query
        )
        return Fixture(
            manager: manager,
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
        let liveTab = Tab(
            webViewSessions: fixture.manager.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        liveTab.bindToShortcutPin(pin)
        liveTab.profileId = profileID
        liveTab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: fixture.manager)
        )
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

@MainActor
private final class LateBoundTabSplitCoordinationPort:
    TabSplitCoordinationPort {
    var base: (any TabSplitCoordinationPort)?

    func stageTabClosures(
        _ tabIds: Set<UUID>
    ) -> (any TabSplitClosureSettlement)? {
        base?.stageTabClosures(tabIds)
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        base?.visibleSplitTabIds(for: windowId) ?? []
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        base?.isTabVisibleInSplit(tabId, in: windowId) ?? false
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        base?.isTabActiveInSplit(tabId, in: windowId) ?? false
    }
}
