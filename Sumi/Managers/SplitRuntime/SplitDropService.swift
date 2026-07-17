import CoreGraphics
import Foundation
import SumiDomain

@MainActor
final class SplitDropTopologyTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let membership: SplitGroupMembershipQuery
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let launcherPlacement: ShortcutSplitLauncherPlacementService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        membership: SplitGroupMembershipQuery,
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        launcherPlacement: ShortcutSplitLauncherPlacementService
    ) {
        self.structuralLookup = structuralLookup
        self.membership = membership
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.launcherPlacement = launcherPlacement
    }

    func perform(
        _ operation: @MainActor @Sendable () -> Bool
    ) -> Bool {
        structuralLookup.withTransaction(operation)
    }

    func memberID(for tab: Tab) -> SplitMemberID {
        membership.memberID(for: tab)
    }

    func group(containing memberID: SplitMemberID) -> SumiDomain.SplitGroup? {
        splitGroups.group(containing: memberID)
    }

    var groups: [SumiDomain.SplitGroup] { splitGroups.groups }

    func commit(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        releasedMembers: [SplitMember]
    ) -> Bool {
        guard let restorations = launcherPlacement.prepareRestorations(
            for: releasedMembers
        ) else { return false }
        return mutations.replaceAllAtomically(
            expected: expected,
            with: replacement,
            applying: { restorations.applyAndCommit() }
        )
    }

    func flushPendingWritesForRead() {
        structuralLookup.flushPendingWritesForRead()
    }
}

/// Commits one drag/drop intent as a single exact split-store transaction.
/// Hit testing is handled by the resolver family; this service owns only the
/// structural move and the resulting window-local selection.
@MainActor
final class SplitDropService {
    private let topology: SplitDropTopologyTransaction
    private let memberResolver: SplitRuntimeMemberResolver
    private let regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction
    private let presentations: any SplitDropPresentationReconciling
    private let notifyLimit: @MainActor (BrowserWindowState) -> Void

    init(
        topology: SplitDropTopologyTransaction,
        memberResolver: SplitRuntimeMemberResolver,
        regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction,
        presentations: any SplitDropPresentationReconciling,
        notifyLimit: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.topology = topology
        self.memberResolver = memberResolver
        self.regularShortcutSidebarDrop = regularShortcutSidebarDrop
        self.presentations = presentations
        self.notifyLimit = notifyLimit
    }

    @discardableResult
    func drop(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard tab.representsSumiNativeSurface == false else {
            return false
        }
        return topology.perform {
            commitDrop(tab, on: target, in: windowState)
        }
    }

    private func commitDrop(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        let incomingID = topology.memberID(for: tab)

        let sourceGroup = topology.group(
            containing: incomingID
        )
        let targetGroup = topology.group(
            containing: target.targetMemberID
        )
        if case .regularTab = incomingID,
           let targetGroup,
           targetGroup.container.isShortcutSidebar {
            return insertRegularTabAsShortcut(
                tab,
                sourceMemberID: incomingID,
                into: targetGroup,
                target: target,
                windowState: windowState
            )
        }
        guard let incoming = memberResolver.resolveExisting(
            tab,
            sourceGroup: sourceGroup,
            in: windowState
        ) else {
            return false
        }

        if let targetGroup, targetGroup.id == sourceGroup?.id {
            return rearrange(
                incoming,
                in: targetGroup,
                target: target,
                windowState: windowState
            )
        }
        if let targetGroup {
            return insert(
                incoming,
                sourceGroup: sourceGroup,
                into: targetGroup,
                target: target,
                windowState: windowState
            )
        }
        return createGroup(
            incoming,
            sourceGroup: sourceGroup,
            target: target,
            windowState: windowState
        )
    }

    private func rearrange(
        _ incoming: ResolvedSplitRuntimeMember,
        in group: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard incoming.member.memberID != target.targetMemberID else {
            return false
        }
        let updatedTree = SplitDropGroupAlgebra.resolvedTree(
            for: incoming.member,
            in: group,
            target: target
        )
        guard let updatedTree,
              let replacement = group.replacingLayoutTree(with: updatedTree)
        else {
            return false
        }
        let expectedGroups = topology.groups
        guard let groupIndex = expectedGroups.firstIndex(where: { $0 == group })
        else { return false }
        var replacementGroups = expectedGroups
        replacementGroups[groupIndex] = replacement
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: windowState.id,
            sourceGroup: group,
            targetGroup: group,
            committedTargetGroupID: replacement.id,
            movingMemberID: incoming.member.memberID,
            activatedMemberID: incoming.member.memberID,
            replacementGroups: replacementGroups
        )
        guard commit(
            expected: expectedGroups,
            replacement: replacementGroups,
            effect: effect
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func insert(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard !targetGroup.container.isShortcutSidebar
                || memberResolver.canJoinShortcutSidebar(
                    incoming.member.memberID,
                    group: targetGroup
                ), memberResolver.canMoveShortcut(
                    incoming.member.memberID,
                    from: sourceGroup,
                    into: targetGroup.container
                ) else {
            // A regular tab must first complete the existing atomic regular →
            // shortcut conversion; mutating the group ahead of it would leave
            // two durable identities for one page.
            return false
        }
        if target.side != .center,
           targetGroup.memberIDs.count >= SumiDomain.SplitGroup.maximumMembers {
            notifyLimit(windowState)
            return false
        }

        guard let updatedTree = SplitDropGroupAlgebra.resolvedTree(
            for: incoming.member,
            in: targetGroup,
            target: target
        ), let replacementTarget = targetGroup.replacingLayoutTree(
            with: updatedTree
        ) else {
            return false
        }

        let expected = topology.groups
        let replacement = SplitDropGroupAlgebra.replacingGroups(
            expected,
            sourceGroup: sourceGroup,
            movingMemberID: incoming.member.memberID,
            targetGroup: targetGroup,
            replacementTarget: replacementTarget
        )
        let effect = SplitDropCommitEffect.resolving(
                callerWindowID: windowState.id,
                sourceGroup: sourceGroup,
                targetGroup: targetGroup,
                committedTargetGroupID: replacementTarget.id,
                movingMemberID: incoming.member.memberID,
                activatedMemberID: incoming.member.memberID,
                replacementGroups: replacement
            )
        guard commit(
            expected: expected,
            replacement: replacement,
            effect: effect
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func createGroup(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard incoming.member.memberID != target.targetMemberID,
              let targetMember = memberResolver.makeMember(
                  for: target.targetMemberID,
                  windowState: windowState
              ),
              let targetLiveTab = memberResolver.liveTab(
                  for: target.targetMemberID,
                  in: windowState
              ), targetLiveTab.representsSumiNativeSurface == false,
              memberResolver.canCreateShortcutGroup(
                  incoming: incoming.member.memberID,
                  target: targetMember.memberID,
                  in: windowState
              ) else {
            return false
        }

        let orderedMembers: [SplitMember]
        if target.side.insertsBeforeTarget {
            orderedMembers = [incoming.member, targetMember]
        } else {
            orderedMembers = [targetMember, incoming.member]
        }
        let layoutKind: SplitLayoutKind = target.side == .top
            || target.side == .bottom
            ? .horizontal
            : .vertical
        let container = memberResolver.initialContainer(
            incoming: incoming.member.memberID,
            target: targetMember.memberID,
            windowState: windowState
        )
        guard memberResolver.canMoveShortcut(
                  incoming.member.memberID,
                  from: sourceGroup,
                  into: container
              ), let group = SumiDomain.SplitGroup.make(
            members: orderedMembers,
            layoutKind: layoutKind,
            container: container
        ) else {
            return false
        }

        let expected = topology.groups
        var replacement = SplitDropGroupAlgebra.removingSourceGroup(
            sourceGroup,
            memberID: incoming.member.memberID,
            from: expected
        )
        replacement.append(group)
        let effect = SplitDropCommitEffect.resolving(
                callerWindowID: windowState.id,
                sourceGroup: sourceGroup,
                targetGroup: nil,
                committedTargetGroupID: group.id,
                movingMemberID: incoming.member.memberID,
                activatedMemberID: incoming.member.memberID,
                replacementGroups: replacement
            )
        guard commit(
            expected: expected,
            replacement: replacement,
            effect: effect
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func insertRegularTabAsShortcut(
        _ tab: Tab,
        sourceMemberID: SplitMemberID,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        if target.side != .center,
           targetGroup.memberIDs.count >= SumiDomain.SplitGroup.maximumMembers {
            notifyLimit(windowState)
            return false
        }
        guard regularShortcutSidebarDrop.commit(
            tab: tab,
            sourceMemberID: sourceMemberID,
            targetGroup: targetGroup,
            target: target,
            windowState: windowState
        ) else { return false }
        topology.flushPendingWritesForRead()
        return true
    }

    private func commit(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        effect: SplitDropCommitEffect
    ) -> Bool {
        topology.commit(
            expected: expected,
            replacement: replacement,
            releasedMembers: effect.releasedMembers
        )
    }
}
