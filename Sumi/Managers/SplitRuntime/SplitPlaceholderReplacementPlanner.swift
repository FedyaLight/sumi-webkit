import Foundation
import SumiDomain

@MainActor
struct SplitPlaceholderReplacementPlan {
    let authority: SplitPlaceholderRuntimeAuthority
    let placeholder: Tab
    let expectedGroups: [SumiDomain.SplitGroup]
    let replacementGroups: [SumiDomain.SplitGroup]
    let effect: SplitDropCommitEffect
}

/// Resolves and revalidates only canonical split/Tab identities. It has no
/// mutation or presentation capability.
@MainActor
final class SplitPlaceholderReplacementQuery {
    private let regularTabs: RegularTabCollectionOwner
    private let splitGroups: SplitGroupStore
    private let membership: SplitGroupMembershipQuery
    private let liveShortcuts: LiveShortcutTabRegistry
    private let members: SplitRuntimeMemberResolver

    init(
        regularTabs: RegularTabCollectionOwner,
        splitGroups: SplitGroupStore,
        membership: SplitGroupMembershipQuery,
        liveShortcuts: LiveShortcutTabRegistry,
        members: SplitRuntimeMemberResolver
    ) {
        self.regularTabs = regularTabs
        self.splitGroups = splitGroups
        self.membership = membership
        self.liveShortcuts = liveShortcuts
        self.members = members
    }

    func plan(
        tab: Tab,
        placeholder: Tab,
        window: BrowserWindowState
    ) -> SplitPlaceholderReplacementPlan? {
        let placeholderTabID = placeholder.id
        let placeholderID = SplitMemberID.regularTab(placeholderTabID)
        guard tab.representsSumiNativeSurface == false,
              regularTabs.tab(for: placeholderTabID) === placeholder,
              let targetGroup = splitGroups.group(containing: placeholderID)
        else { return nil }

        let incomingID = membership.memberID(for: tab)
        let sourceGroup = splitGroups.group(containing: incomingID)
        guard let member = sourceGroup?.member(for: incomingID)
                ?? members.makeMember(for: incomingID, windowState: window),
              canonicalTab(for: incomingID, in: window.id) === tab,
              targetGroup.container.isShortcutSidebar == false
                || members.canJoinShortcutSidebar(incomingID, group: targetGroup),
              members.canMoveShortcut(
                  incomingID,
                  from: sourceGroup,
                  into: targetGroup.container
              ) else { return nil }

        let target = SplitDropTarget(
            targetMemberID: placeholderID,
            side: .center,
            targetRect: .zero,
            previewStyle: .center,
            intent: .paneCenter
        )
        guard let tree = SplitDropGroupAlgebra.resolvedTree(
            for: member,
            in: targetGroup,
            target: target
        ), let replacementTarget = targetGroup.replacingLayoutTree(with: tree)
        else { return nil }

        let expected = splitGroups.groups
        let replacement = replacementGroups(
            expected,
            sourceGroup: sourceGroup,
            incomingID: incomingID,
            targetGroup: targetGroup,
            replacementTarget: replacementTarget
        )
        guard replacement != expected else { return nil }
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: window.id,
            sourceGroup: sourceGroup,
            targetGroup: targetGroup,
            committedTargetGroupID: replacementTarget.id,
            movingMemberID: incomingID,
            activatedMemberID: incomingID,
            replacementGroups: replacement
        )
        return SplitPlaceholderReplacementPlan(
            authority: SplitPlaceholderRuntimeAuthority(
                window: window,
                expectedSpaceID: window.currentSpaceId,
                placeholder: placeholder,
                placeholderID: placeholderTabID,
                incoming: tab,
                incomingID: incomingID,
                regularTabs: regularTabs,
                liveShortcuts: liveShortcuts
            ),
            placeholder: placeholder,
            expectedGroups: expected,
            replacementGroups: replacement,
            effect: effect
        )
    }

    private func replacementGroups(
        _ expected: [SumiDomain.SplitGroup],
        sourceGroup: SumiDomain.SplitGroup?,
        incomingID: SplitMemberID,
        targetGroup: SumiDomain.SplitGroup,
        replacementTarget: SumiDomain.SplitGroup
    ) -> [SumiDomain.SplitGroup] {
        if sourceGroup?.id == targetGroup.id {
            return expected.map {
                $0.id == targetGroup.id ? replacementTarget : $0
            }
        }
        return SplitDropGroupAlgebra.replacingGroups(
            expected,
            sourceGroup: sourceGroup,
            movingMemberID: incomingID,
            targetGroup: targetGroup,
            replacementTarget: replacementTarget
        )
    }

    private func canonicalTab(
        for memberID: SplitMemberID,
        in windowID: UUID
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            return regularTabs.tab(for: tabID)
        case .shortcutPin(let pinID):
            return liveShortcuts.tab(for: pinID, in: windowID)
        }
    }
}

/// Assembles exact topology, placeholder-retirement, and presentation
/// participants after the read-only query has admitted the move.
@MainActor
final class SplitPlaceholderReplacementPlanner {
    private let query: SplitPlaceholderReplacementQuery
    private let launcherRelease: ShortcutSplitLauncherReleasePlanner
    private let splitMutations: SplitGroupMutationService
    private let retirement: EmptySplitPlaceholderRetirementService
    private let presentations: any SplitDropPresentationReconciling

    init(
        query: SplitPlaceholderReplacementQuery,
        launcherRelease: ShortcutSplitLauncherReleasePlanner,
        splitMutations: SplitGroupMutationService,
        retirement: EmptySplitPlaceholderRetirementService,
        presentations: any SplitDropPresentationReconciling
    ) {
        self.query = query
        self.launcherRelease = launcherRelease
        self.splitMutations = splitMutations
        self.retirement = retirement
        self.presentations = presentations
    }

    func prepare(
        tab: Tab,
        placeholder: Tab,
        window: BrowserWindowState
    ) -> SplitPlaceholderReplacementReceipt? {
        guard let plan = query.plan(
            tab: tab,
            placeholder: placeholder,
            window: window
        ), let launcherRelease = launcherRelease.prepareNoMoveRelease(
            for: plan.effect.releasedMembers
        ), let placeholderRetirement = retirement.prepare(plan.placeholder),
           let topology = splitMutations.prepareReplaceAll(
               expected: plan.expectedGroups,
               with: plan.replacementGroups,
               persist: false
           ) else { return nil }

        return SplitPlaceholderReplacementReceipt(
            authority: plan.authority,
            topology: SplitPlaceholderTopologyMutation(
                topology: topology,
                launcherRelease: launcherRelease,
                placeholderRetirement: placeholderRetirement
            ),
            presentations: presentations,
            effect: plan.effect
        )
    }
}
