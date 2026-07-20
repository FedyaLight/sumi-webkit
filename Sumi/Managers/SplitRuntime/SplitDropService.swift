import CoreGraphics
import Foundation
import SumiDomain

@MainActor
final class SplitDropTopologyTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let membership: SplitGroupMembershipQuery
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        membership: SplitGroupMembershipQuery,
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService
    ) {
        self.structuralLookup = structuralLookup
        self.membership = membership
        self.splitGroups = splitGroups
        self.mutations = mutations
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
        releasedMembers _: [SplitMember]
    ) -> Bool {
        mutations.replaceAll(expected: expected, with: replacement)
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
    private let shortcutMemberRelocation: SplitGroupShortcutMemberRelocation
    private let duplication: SplitTabDuplicationService
    private let presentations: any SplitDropPresentationReconciling
    private let notifyLimit: @MainActor (BrowserWindowState) -> Void

    init(
        topology: SplitDropTopologyTransaction,
        memberResolver: SplitRuntimeMemberResolver,
        regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction,
        shortcutMemberRelocation: SplitGroupShortcutMemberRelocation,
        duplication: SplitTabDuplicationService,
        presentations: any SplitDropPresentationReconciling,
        notifyLimit: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.topology = topology
        self.memberResolver = memberResolver
        self.regularShortcutSidebarDrop = regularShortcutSidebarDrop
        self.shortcutMemberRelocation = shortcutMemberRelocation
        self.duplication = duplication
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
            commitDrop(
                topology.memberID(for: tab),
                sourceTab: tab,
                on: target,
                in: windowState
            )
        }
    }

    /// Sidebar shortcut drags carry the durable pin identity. Resolving them
    /// through a synthetic drag-proxy tab loses that identity at the runtime
    /// boundary, so sidebar-originated drops enter through this overload.
    @discardableResult
    func drop(
        _ memberID: SplitMemberID,
        sourceTab: Tab? = nil,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        let candidate: Tab? = switch memberID {
        case .regularTab: sourceTab
        case .shortcutPin: nil
        }
        guard let resolvedSourceTab = memberResolver.liveTab(
            for: memberID,
            candidate: candidate,
            in: windowState
        ), resolvedSourceTab.representsSumiNativeSurface == false,
              let member = memberResolver.makeMember(
                  for: memberID,
                  windowState: windowState
              ) else {
            return false
        }
        return topology.perform {
            commitDrop(
                memberID,
                sourceTab: resolvedSourceTab,
                resolvedIncoming: ResolvedSplitRuntimeMember(
                    member: member,
                    liveTab: resolvedSourceTab
                ),
                on: target,
                in: windowState
            )
        }
    }

    private func commitDrop(
        _ incomingID: SplitMemberID,
        sourceTab tab: Tab,
        resolvedIncoming: ResolvedSplitRuntimeMember? = nil,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
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
        guard let incoming = resolvedIncoming ?? memberResolver.resolveExisting(
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
        if case .regularTabs = targetGroup.container,
           case .shortcutPin = incoming.member.memberID {
            return insertDuplicatingShortcut(
                incoming,
                into: targetGroup,
                target: target,
                windowState: windowState
            )
        }
        if targetGroup.container.isShortcutSidebar,
           case .shortcutPin = incoming.member.memberID,
           memberResolver.canJoinShortcutSidebar(
               incoming.member.memberID,
               group: targetGroup
           ) == false {
            return insertMovingShortcut(
                incoming,
                sourceGroup: sourceGroup,
                into: targetGroup,
                target: target,
                windowState: windowState
            )
        }
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

    private func insertMovingShortcut(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard target.side != .center else { return false }
        guard targetGroup.memberIDs.count < SumiDomain.SplitGroup.maximumMembers
        else {
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
        guard shortcutMemberRelocation.move(
            incoming.member.memberID,
            into: targetGroup.container,
            expectedGroups: expected,
            replacementGroups: replacement
        ) else {
            return false
        }
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
              ) else {
            return false
        }

        let container = memberResolver.initialContainer(
            incoming: incoming.member.memberID,
            target: targetMember.memberID,
            windowState: windowState
        )
        if case .regularTabs = container,
           incoming.member.memberID.isShortcutPin
                || targetMember.memberID.isShortcutPin {
            guard let targetLiveTab = memberResolver.liveTab(
                for: target.targetMemberID,
                in: windowState
            ), targetLiveTab.representsSumiNativeSurface == false else {
                return false
            }
            return createRegularGroupByDuplicatingLaunchers(
                incoming,
                sourceGroup: sourceGroup,
                targetMember: targetMember,
                targetLiveTab: targetLiveTab,
                target: target,
                container: container,
                windowState: windowState
            )
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
        guard let group = SumiDomain.SplitGroup.make(
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
        if container.isShortcutSidebar,
           incoming.member.memberID.isShortcutPin,
           memberResolver.canJoinShortcutSidebar(
               incoming.member.memberID,
               group: group
           ) == false {
            guard shortcutMemberRelocation.move(
                incoming.member.memberID,
                into: container,
                expectedGroups: expected,
                replacementGroups: replacement
            ) else {
                return false
            }
            presentations.reconcile(effect)
            return true
        }
        guard commit(
            expected: expected,
            replacement: replacement,
            effect: effect
        ) else {
            return false
        }
        presentations.reconcile(effect)
        return true
    }

    private func insertDuplicatingShortcut(
        _ incoming: ResolvedSplitRuntimeMember,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        if target.side != .center,
           targetGroup.memberIDs.count >= SumiDomain.SplitGroup.maximumMembers {
            notifyLimit(windowState)
            return false
        }
        let copy = duplication.duplicate(incoming.liveTab, in: windowState)
        let member = SplitMember.regularTab(copy.id)
        guard let updatedTree = SplitDropGroupAlgebra.resolvedTree(
            for: member,
            in: targetGroup,
            target: target
        ), let replacementTarget = targetGroup.replacingLayoutTree(
            with: updatedTree
        ) else {
            duplication.discard(copy)
            return false
        }
        let expected = topology.groups
        guard let index = expected.firstIndex(where: { $0 == targetGroup }) else {
            duplication.discard(copy)
            return false
        }
        var replacement = expected
        replacement[index] = replacementTarget
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: windowState.id,
            sourceGroup: nil,
            targetGroup: targetGroup,
            committedTargetGroupID: replacementTarget.id,
            movingMemberID: member,
            activatedMemberID: member,
            replacementGroups: replacement
        )
        guard commit(
            expected: expected,
            replacement: replacement,
            effect: effect
        ) else {
            duplication.discard(copy)
            return false
        }
        presentations.reconcile(effect)
        return true
    }

    private func createRegularGroupByDuplicatingLaunchers(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        targetMember: SplitMember,
        targetLiveTab: Tab,
        target: SplitDropTarget,
        container: SplitGroupContainer,
        windowState: BrowserWindowState
    ) -> Bool {
        var copies: [Tab] = []
        func regularMember(_ member: SplitMember, liveTab: Tab) -> SplitMember {
            guard member.isShortcutPin else { return member }
            let copy = duplication.duplicate(liveTab, in: windowState)
            copies.append(copy)
            return .regularTab(copy.id)
        }

        let incomingMember = regularMember(
            incoming.member,
            liveTab: incoming.liveTab
        )
        let regularTarget = regularMember(targetMember, liveTab: targetLiveTab)
        let orderedMembers = target.side.insertsBeforeTarget
            ? [incomingMember, regularTarget]
            : [regularTarget, incomingMember]
        let layoutKind: SplitLayoutKind = target.side == .top
            || target.side == .bottom ? .horizontal : .vertical
        guard let group = SumiDomain.SplitGroup.make(
            members: orderedMembers,
            layoutKind: layoutKind,
            container: container
        ) else {
            copies.forEach { duplication.discard($0) }
            return false
        }

        let expected = topology.groups
        let movesOriginalIncoming = incomingMember == incoming.member
        var replacement = SplitDropGroupAlgebra.removingSourceGroup(
            movesOriginalIncoming ? sourceGroup : nil,
            memberID: incoming.member.memberID,
            from: expected
        )
        replacement.append(group)
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: windowState.id,
            sourceGroup: movesOriginalIncoming ? sourceGroup : nil,
            targetGroup: nil,
            committedTargetGroupID: group.id,
            movingMemberID: incomingMember,
            activatedMemberID: incomingMember,
            replacementGroups: replacement
        )
        guard commit(
            expected: expected,
            replacement: replacement,
            effect: effect
        ) else {
            copies.forEach { duplication.discard($0) }
            return false
        }
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
