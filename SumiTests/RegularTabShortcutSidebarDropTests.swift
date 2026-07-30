import Combine
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
extension RegularTabShortcutConversionServiceTests {
    func testShortcutSidebarDropMovesStableMemberAndEveryWindowToTargetGroup() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let states = [first.id: first, second.id: second]
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in first.id }
            )
        ))
        let space = Space(
            name: "Space",
            profileId: profile.id
        )
        tabManager.spaceStateOwner.append(space)
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
                .shortcutPin(firstPin.id),
                .shortcutPin(secondPin.id),
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
        XCTAssertEqual(
            replacementTarget.member(for: prepared.member.memberID),
            prepared.member
        )
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
        let tabManager = BrowserManager()
        let space = Space(name: "Space")
        tabManager.spaceStateOwner.append(space)
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
                .shortcutPin(firstPin.id),
                .shortcutPin(secondPin.id),
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
        tabManager: BrowserManager
    ) -> RegularTabShortcutSplitPresentationPreparation {
        let currentWindows = { @MainActor in windows }
        let presentations = WindowSplitPresentationSynchronizer(
            preparation: WindowSplitPresentationPreparationService(
                drafts: WindowSplitPresentationDraftPlanner(
                    splitGroups: tabManager.splitGroupStore,
                    regularTabs: tabManager.regularTabCollectionOwner,
                    pins: tabManager.shortcutPinCollectionStateOwner
                ),
                activation: tabManager.shortcutPresentationActivation,
                regularTabs: tabManager.regularTabCollectionOwner,
                validator: WindowSplitPresentationSettlementValidator(
                    splitGroups: tabManager.splitGroupStore,
                    regularTabs: tabManager.regularTabCollectionOwner,
                    liveShortcuts: tabManager.liveShortcutTabs,
                    currentWindows: currentWindows
                ),
                windows: currentWindows
            ),
            splitGroups: tabManager.splitGroupStore,
            members: tabManager.splitMembers,
            materialization: tabManager.splitMaterialization,
            terminalEffects: WindowSplitPresentationEffectExecutor(
                selection: tabManager.browserTabSelection,
                updates: tabManager.splitUpdateChannel,
                visuals: tabManager.shellRuntime.windowVisuals,
                persistence: tabManager.windowSessionPersistenceCoordinator
            )
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
