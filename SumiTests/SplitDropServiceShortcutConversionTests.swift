import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitDropServiceShortcutConversionTests: XCTestCase {
    func testDurablePinnedMemberCreatesPinnedSplitWithoutDragProxyIdentity()
        throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let sourcePin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: fixture.targetPins.count,
            launchURL: URL(string: "https://pinned-source.example")!,
            title: "Pinned Source"
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                fixture.targetPins + [sourcePin],
                for: fixture.space.id
            )
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [fixture.sourceGroup],
            persist: false
        ))

        let dragProxy = Tab(loadsCachedFaviconOnInit: false)
        dragProxy.bindToShortcutPin(sourcePin)
        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(sourcePin.id),
            sourceTab: dragProxy,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(fixture.targetPins[0].id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .shortcutPin(sourcePin.id)
            )
        )
        XCTAssertEqual(
            Set(group.memberIDs),
            Set([
                .shortcutPin(sourcePin.id),
                .shortcutPin(fixture.targetPins[0].id),
            ])
        )
        guard case .shortcutSidebar(let spaceID, _, nil, _) = group.container else {
            return XCTFail("Expected a pinned split group")
        }
        XCTAssertEqual(spaceID, fixture.space.id)
        let materialized = try XCTUnwrap(
            fixture.manager.liveShortcutTabs.tab(
                for: sourcePin.id,
                in: fixture.window.id
            )
        )
        XCTAssertFalse(materialized === dragProxy)
    }

    func testPinnedLauncherMovesIntoFavoriteSplitAsThirdMember() throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let profileID = try XCTUnwrap(fixture.space.profileId)
        let favoritePins = (0..<2).map { index in
            ShortcutPin(
                id: UUID(),
                role: .favorite,
                profileId: profileID,
                index: index,
                launchURL: URL(string: "https://favorite-\(index).example")!,
                title: "Favorite \(index)"
            )
        }
        let sourcePin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: 0,
            launchURL: URL(string: "https://pinned-source.example")!,
            title: "Pinned Source"
        )
        fixture.manager.structuralCollectionMutationOwner.setPinnedTabs(
            favoritePins,
            for: profileID
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([sourcePin], for: fixture.space.id)
        let favoriteGroup = try XCTUnwrap(SplitGroup.make(
            members: favoritePins.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .favoriteSidebar(profileId: profileID, index: 0)
        ))
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [favoriteGroup],
            persist: false
        ))

        let dragProxy = Tab(loadsCachedFaviconOnInit: false)
        dragProxy.bindToShortcutPin(sourcePin)
        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(sourcePin.id),
            sourceTab: dragProxy,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(favoritePins[0].id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let committed = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: favoriteGroup.id)
        )
        XCTAssertEqual(committed.memberIDs.count, 3)
        XCTAssertTrue(committed.contains(.shortcutPin(sourcePin.id)))
        XCTAssertNil(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id)
                .first(where: { $0.id == sourcePin.id })
        )
        XCTAssertEqual(
            fixture.manager.shortcutPinCollectionStateOwner
                .favoritePins(for: profileID)
                .first(where: { $0.id == sourcePin.id })?.role,
            .favorite
        )
    }

    func testPinnedLauncherSplitsWithStandaloneFavoriteByMovingIntoFavorite()
        throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let profileID = try XCTUnwrap(fixture.space.profileId)
        let source = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: 0,
            launchURL: URL(string: "https://pinned-source.example")!,
            title: "Pinned Source"
        )
        let target = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://favorite-target.example")!,
            title: "Favorite Target"
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([source], for: fixture.space.id)
        fixture.manager.structuralCollectionMutationOwner.setPinnedTabs(
            [target],
            for: profileID
        )
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [],
            persist: false
        ))
        let regularCount = fixture.manager.regularTabCollectionOwner
            .tabs(in: fixture.space.id).count

        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(source.id),
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(target.id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(containing: .shortcutPin(target.id))
        )
        XCTAssertEqual(
            group.memberIDs,
            [.shortcutPin(target.id), .shortcutPin(source.id)]
        )
        guard case .favoriteSidebar(let ownerProfileID, _) = group.container else {
            return XCTFail("Expected the target Favorite to own the group")
        }
        XCTAssertEqual(ownerProfileID, profileID)
        XCTAssertNil(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id)
                .first(where: { $0.id == source.id })
        )
        XCTAssertEqual(
            fixture.manager.shortcutPinCollectionStateOwner
                .favoritePins(for: profileID)
                .first(where: { $0.id == source.id })?.role,
            .favorite
        )
        XCTAssertEqual(
            fixture.manager.regularTabCollectionOwner
                .tabs(in: fixture.space.id).count,
            regularCount
        )
    }

    func testFavoriteLauncherSplitsWithStandalonePinnedByMovingIntoPinned()
        throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let profileID = try XCTUnwrap(fixture.space.profileId)
        let source = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://favorite-source.example")!,
            title: "Favorite Source"
        )
        let target = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: 0,
            launchURL: URL(string: "https://pinned-target.example")!,
            title: "Pinned Target"
        )
        fixture.manager.structuralCollectionMutationOwner.setPinnedTabs(
            [source],
            for: profileID
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([target], for: fixture.space.id)
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [],
            persist: false
        ))
        let regularCount = fixture.manager.regularTabCollectionOwner
            .tabs(in: fixture.space.id).count

        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(source.id),
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(target.id),
                side: .left,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(containing: .shortcutPin(target.id))
        )
        XCTAssertEqual(
            group.memberIDs,
            [.shortcutPin(source.id), .shortcutPin(target.id)]
        )
        guard case .shortcutSidebar(let spaceID, _, let folderID, _) =
                group.container else {
            return XCTFail("Expected the target Pinned item to own the group")
        }
        XCTAssertEqual(spaceID, fixture.space.id)
        XCTAssertNil(folderID)
        XCTAssertNil(
            fixture.manager.shortcutPinCollectionStateOwner
                .favoritePins(for: profileID)
                .first(where: { $0.id == source.id })
        )
        XCTAssertEqual(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id)
                .first(where: { $0.id == source.id })?.role,
            .spacePinned
        )
        XCTAssertEqual(
            fixture.manager.regularTabCollectionOwner
                .tabs(in: fixture.space.id).count,
            regularCount
        )
    }

    func testPinnedMemberSplitsWithRegularTabByConvertingLauncher() throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: fixture.targetPins.count,
            launchURL: URL(string: "https://pinned-source.example")!,
            title: "Pinned Source"
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                fixture.targetPins + [pin],
                for: fixture.space.id
            )
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [],
            persist: false
        ))

        let dragProxy = Tab(loadsCachedFaviconOnInit: false)
        dragProxy.bindToShortcutPin(pin)
        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(pin.id),
            sourceTab: dragProxy,
            on: SplitDropTarget(
                targetMemberID: .regularTab(fixture.source.id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .regularTab(fixture.source.id)
            )
        )
        guard case .regularTabs(let spaceID) = group.container else {
            return XCTFail("Expected a regular split group")
        }
        XCTAssertEqual(spaceID, fixture.space.id)
        XCTAssertEqual(group.memberIDs.count, 2)
        XCTAssertTrue(group.memberIDs.allSatisfy { memberID in
            if case .regularTab = memberID { return true }
            return false
        })
        XCTAssertFalse(group.contains(.shortcutPin(pin.id)))
        XCTAssertNil(
            fixture.manager.shortcutPinCollectionStateOwner.shortcutPin(
                by: pin.id
            )
        )
    }

    func testPinnedLauncherJoinsRegularSplitByConvertingWithoutCopy() throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: fixture.space.id,
            index: fixture.targetPins.count,
            launchURL: URL(string: "https://pinned-incoming.example")!,
            title: "Pinned Incoming"
        )
        fixture.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                fixture.targetPins + [pin],
                for: fixture.space.id
            )

        XCTAssertTrue(fixture.service.drop(
            .shortcutPin(pin.id),
            on: SplitDropTarget(
                targetMemberID: .regularTab(fixture.source.id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.sourceGroup.id)
        )
        XCTAssertEqual(group.memberIDs.count, 3)
        XCTAssertTrue(group.memberIDs.allSatisfy { memberID in
            if case .regularTab = memberID { return true }
            return false
        })
        XCTAssertNil(
            fixture.manager.shortcutPinCollectionStateOwner.shortcutPin(
                by: pin.id
            )
        )
        XCTAssertEqual(
            fixture.manager.regularTabCollectionOwner
                .tabs(in: fixture.space.id)
                .filter { group.contains(.regularTab($0.id)) }
                .count,
            3
        )
    }

    func testRegularTabSplitsWithStandalonePinnedByConvertingIntoPinned()
        throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        fixture.probe.reconcilesPresentations = false
        XCTAssertTrue(fixture.manager.splitGroupMutations.replaceAll(
            expected: [fixture.sourceGroup, fixture.targetGroup],
            with: [],
            persist: false
        ))
        let targetPin = fixture.targetPins[0]

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(targetPin.id),
                side: .left,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        let group = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(
                containing: .shortcutPin(targetPin.id)
            )
        )
        guard case .shortcutSidebar(
            let spaceID,
            _,
            let folderID,
            _
        ) = group.container else {
            return XCTFail("Expected the pinned target to own the group")
        }
        XCTAssertEqual(spaceID, fixture.space.id)
        XCTAssertNil(folderID)
        XCTAssertEqual(group.memberIDs.count, 2)
        XCTAssertTrue(group.memberIDs.allSatisfy(\.isShortcutPin))
        XCTAssertFalse(
            fixture.manager.regularTabCollectionOwner.contains(fixture.source)
        )
        XCTAssertFalse(group.contains(.regularTab(fixture.source.id)))
        let groupPinIDs = Set(
            group.memberIDs.compactMap(\.shortcutPinID)
        )
        let pinnedIDs = Set(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id)
                .map(\.id)
        )
        XCTAssertTrue(groupPinIDs.isSubset(of: pinnedIDs))
        XCTAssertTrue(groupPinIDs.contains(targetPin.id))
        XCTAssertEqual(groupPinIDs.count, 2)
        let visualItems = fixture.manager.splitGroupSidebarOrdering
            .topLevelItems(for: fixture.space.id)
        XCTAssertEqual(
            visualItems.filter {
                if case .splitGroup = $0 { return true }
                return false
            },
            [.splitGroup(group.id)]
        )
        XCTAssertFalse(visualItems.contains(.shortcut(targetPin.id)))
        XCTAssertEqual(
            Set(visualItems.map(\.id)).count,
            visualItems.count
        )
    }

    func testEdgeDropCollapsesTwoMemberSourceAndActivatesExactPin() throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        let target = SplitDropTarget(
            targetMemberID: .shortcutPin(fixture.targetPins[0].id),
            side: .right,
            targetRect: .zero
        )

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: target,
            in: fixture.window
        ))

        let effect = try XCTUnwrap(fixture.probe.effects.first)
        guard case .shortcutPin(let pinID) = effect.preferredActiveMemberID else {
            return XCTFail("Expected the generated shortcut member to activate")
        }
        let committedTarget = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.targetGroup.id)
        )
        XCTAssertNil(
            fixture.manager.splitGroupStore.group(id: fixture.sourceGroup.id)
        )
        XCTAssertEqual(committedTarget.memberIDs.count, 3)
        XCTAssertTrue(committedTarget.contains(.shortcutPin(pinID)))
        XCTAssertEqual(fixture.window.splitSelection?.groupID, committedTarget.id)
        XCTAssertEqual(fixture.window.currentShortcutPinId, pinID)
        let liveTab = try XCTUnwrap(fixture.manager.liveShortcutTabs.tab(
            for: pinID,
            in: fixture.window.id
        ))
        XCTAssertEqual(
            fixture.window.currentTabId,
            liveTab.id
        )
        XCTAssertEqual(effect.previousGroups, [fixture.sourceGroup, fixture.targetGroup])
        XCTAssertEqual(
            effect.affectedGroupIDs,
            Set([fixture.sourceGroup.id, fixture.targetGroup.id])
        )
        XCTAssertEqual(
            effect.releasedMembers.map(\.memberID),
            [.regularTab(fixture.sourceCompanions[0].id)]
        )
    }

    func testCenterDropKeepsReducedThreeMemberSourceAndReportsReleasedTarget() throws {
        let fixture = try makeFixture(sourceMemberCount: 3)
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        let displacedPinID = fixture.targetPins[0].id
        let target = SplitDropTarget(
            targetMemberID: .shortcutPin(displacedPinID),
            side: .center,
            targetRect: .zero,
            previewStyle: .center
        )

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: target,
            in: fixture.window
        ))

        let effect = try XCTUnwrap(fixture.probe.effects.first)
        let reducedSource = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.sourceGroup.id)
        )
        let committedTarget = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.targetGroup.id)
        )
        XCTAssertEqual(
            Set(reducedSource.memberIDs),
            Set(fixture.sourceCompanions.map { .regularTab($0.id) })
        )
        XCTAssertFalse(committedTarget.contains(.shortcutPin(displacedPinID)))
        XCTAssertTrue(committedTarget.contains(effect.preferredActiveMemberID))
        XCTAssertEqual(
            effect.releasedMembers.map(\.memberID),
            [.shortcutPin(displacedPinID)]
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: committedTarget.id,
                activeMemberID: effect.preferredActiveMemberID
            )
        )
        XCTAssertEqual(
            fixture.window.currentShortcutPinId,
            effect.preferredActiveMemberID.shortcutPinID
        )
    }

    func testFullTargetRejectsEdgeDropWithoutConversionMutation() throws {
        let fixture = try makeFixture(
            sourceMemberCount: 2,
            targetMemberCount: SumiDomain.SplitGroup.maximumMembers
        )
        defer { fixture.manager.tabRuntimeLifecycle.shutdown() }
        let expectedGroups = fixture.manager.splitGroupStore.groups
        let expectedPins = fixture.manager.shortcutPinCollectionStateOwner
            .spacePinnedPins(for: fixture.space.id).map(\.id)

        XCTAssertFalse(fixture.service.drop(
            fixture.source,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(fixture.targetPins[0].id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        XCTAssertEqual(fixture.manager.splitGroupStore.groups, expectedGroups)
        XCTAssertEqual(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id).map(\.id),
            expectedPins
        )
        XCTAssertTrue(
            fixture.manager.regularTabCollectionOwner.contains(fixture.source)
        )
        XCTAssertTrue(fixture.probe.effects.isEmpty)
        XCTAssertEqual(fixture.probe.limitCount, 1)
    }
}

@MainActor
private extension SplitDropServiceShortcutConversionTests {
    @MainActor
    struct Fixture {
        let manager: BrowserManager
        let window: BrowserWindowState
        let space: Space
        let source: Tab
        let sourceCompanions: [Tab]
        let sourceGroup: SplitGroup
        let targetPins: [ShortcutPin]
        let targetGroup: SplitGroup
        let service: SplitDropService
        let probe: Probe
    }

    final class Probe {
        var effects: [SplitDropCommitEffect] = []
        var limitCount = 0
        var reconcilesPresentations = true
    }

    final class RecordingSplitDropPresentations:
        SplitDropPresentationReconciling {
        private let presentations: WindowSplitPresentationSynchronizer
        private let probe: Probe

        init(
            presentations: WindowSplitPresentationSynchronizer,
            probe: Probe
        ) {
            self.presentations = presentations
            self.probe = probe
        }

        func reconcile(_ effect: SplitDropCommitEffect) {
            probe.effects.append(effect)
            if probe.reconcilesPresentations {
                presentations.reconcile(effect)
            }
        }

        func prepare(
            _ effect: SplitDropCommitEffect,
            sourceGroups: [SplitGroup],
            replacementGroups: [SplitGroup],
            requiredWindow: BrowserWindowState,
            insertionPreview: ShortcutPresentationCatalogInsertionPreview,
            residenceContribution: DisplayedShortcutResidenceContribution
        ) -> PreparedWindowSplitPresentationSettlement? {
            probe.effects.append(effect)
            return presentations.prepare(
                effect,
                sourceGroups: sourceGroups,
                replacementGroups: replacementGroups,
                requiredWindow: requiredWindow,
                insertionPreview: insertionPreview,
                residenceContribution: residenceContribution
            )
        }
    }

    func makeFixture(
        sourceMemberCount: Int,
        targetMemberCount: Int = 2
    ) throws -> Fixture {
        let window = BrowserWindowState()
        let sourceProfile = Profile(name: "Source")
        let probe = Probe()
        let runtime = TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { $0 == sourceProfile.id ? sourceProfile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in window.id },
                executeProfileAssignment: { tab, _, intent in
                    tab.profileAssignment.commit(intent)
                        ? .committed
                        : .stale
                }
            )
        )
        let manager = BrowserManager(runtimePorts: runtime)
        manager.windowRegistry.register(window)
        let space = try XCTUnwrap(manager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: sourceProfile.id
        ))
        let source = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://drop-source.example",
            in: space,
            activate: false
        )
        let companions = (1..<sourceMemberCount).map { index in
            manager.regularTabLifecycleOwner.createNewTab(
                url: "https://drop-companion-\(index).example",
                in: space,
                activate: false
            )
        }
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id)] + companions.map {
                .regularTab($0.id)
            },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        let pins = (0..<targetMemberCount).map {
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: $0,
                launchURL: URL(string: "https://drop-pin-\($0).example")!,
                title: "Pin \($0)"
            )
        }
        manager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            pins,
            for: space.id
        )
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(manager.splitGroupMutations.replaceAll(
            expected: [],
            with: [sourceGroup, targetGroup],
            persist: false
        ))
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        window.splitSelection = WindowSplitSelection(
            groupID: sourceGroup.id,
            activeMemberID: .regularTab(source.id)
        )
        let members = makeTestSplitRuntimeMemberResolver(manager)
        let presentations = makeTestWindowSplitPresentationSynchronizer(
            browser: manager,
            windows: { [window] }
        )
        let recordingPresentations = RecordingSplitDropPresentations(
            presentations: presentations,
            probe: probe
        )
        let service = SplitDropService(
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
                    presentations: recordingPresentations
                ),
            shortcutToRegular: manager.shortcutPinToRegularTab,
            shortcutMemberRelocation:
                manager.splitGroupShortcutMemberRelocation,
            presentations: recordingPresentations,
            notifyLimit: { _ in probe.limitCount += 1 }
        )
        return Fixture(
            manager: manager,
            window: window,
            space: space,
            source: source,
            sourceCompanions: companions,
            sourceGroup: sourceGroup,
            targetPins: pins,
            targetGroup: targetGroup,
            service: service,
            probe: probe
        )
    }
}

private extension SplitMemberID {
    var shortcutPinID: UUID? {
        guard case .shortcutPin(let pinID) = self else { return nil }
        return pinID
    }
}
