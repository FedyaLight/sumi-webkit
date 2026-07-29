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
    private let shortcutToRegular: ShortcutPinToRegularTabService
    private let shortcutMemberRelocation: SplitGroupShortcutMemberRelocation
    private let presentations: any SplitDropPresentationReconciling
    private let notifyLimit: @MainActor (BrowserWindowState) -> Void

    init(
        topology: SplitDropTopologyTransaction,
        memberResolver: SplitRuntimeMemberResolver,
        regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction,
        shortcutToRegular: ShortcutPinToRegularTabService,
        shortcutMemberRelocation: SplitGroupShortcutMemberRelocation,
        presentations: any SplitDropPresentationReconciling,
        notifyLimit: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.topology = topology
        self.memberResolver = memberResolver
        self.regularShortcutSidebarDrop = regularShortcutSidebarDrop
        self.shortcutToRegular = shortcutToRegular
        self.shortcutMemberRelocation = shortcutMemberRelocation
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
        if case .regularTab = incomingID,
           targetGroup == nil,
           let targetPin = memberResolver.shortcutPin(
               for: target.targetMemberID
           ) {
            return regularShortcutSidebarDrop.commit(
                tab: tab,
                sourceMemberID: incomingID,
                standaloneTargetPin: targetPin,
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
            guard sourceGroup == nil else { return false }
            return insertConvertingShortcut(
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
            guard sourceGroup == nil else { return false }
            guard let targetLiveTab = memberResolver.liveTab(
                for: target.targetMemberID,
                in: windowState
            ), targetLiveTab.representsSumiNativeSurface == false else {
                return false
            }
            return createRegularGroupByConvertingLauncher(
                incoming,
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

    private func insertConvertingShortcut(
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
        guard case .shortcutPin(let pinID) = incoming.member.memberID,
              let pin = memberResolver.shortcutPin(
                  for: .shortcutPin(pinID)
              ), let targetSpaceID = regularSpaceID(
                  for: targetGroup,
                  in: windowState,
                  fallback: windowState.currentSpaceId
              ), let tab = shortcutToRegular.promoteForSplitDrop(
                  pin,
                  into: targetSpaceID,
                  preferredWindowID: windowState.id
              ) else { return false }

        topology.flushPendingWritesForRead()
        guard let refreshedTarget = topology.groups.first(where: {
            $0.id == targetGroup.id
        }) else { return false }
        return insert(
            ResolvedSplitRuntimeMember(
                member: .regularTab(tab.id),
                liveTab: tab
            ),
            sourceGroup: nil,
            into: refreshedTarget,
            target: target,
            windowState: windowState
        )
    }

    private func createRegularGroupByConvertingLauncher(
        _ incoming: ResolvedSplitRuntimeMember,
        targetLiveTab: Tab,
        target: SplitDropTarget,
        container: SplitGroupContainer,
        windowState: BrowserWindowState
    ) -> Bool {
        guard case .shortcutPin(let pinID) = incoming.member.memberID,
              let pin = memberResolver.shortcutPin(
                  for: .shortcutPin(pinID)
              ), case .regularTabs(let storedSpaceID) = container,
              let targetSpaceID = storedSpaceID
                  ?? targetLiveTab.spaceId
                  ?? windowState.currentSpaceId,
              let tab = shortcutToRegular.promoteForSplitDrop(
                  pin,
                  into: targetSpaceID,
                  preferredWindowID: windowState.id
              ) else { return false }

        topology.flushPendingWritesForRead()
        return createGroup(
            ResolvedSplitRuntimeMember(
                member: .regularTab(tab.id),
                liveTab: tab
            ),
            sourceGroup: nil,
            target: target,
            windowState: windowState
        )
    }

    private func regularSpaceID(
        for group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState,
        fallback: UUID?
    ) -> UUID? {
        guard case .regularTabs(let storedSpaceID) = group.container else {
            return nil
        }
        if let storedSpaceID { return storedSpaceID }
        return group.memberIDs.compactMap { memberID -> UUID? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return memberResolver.liveTab(
                for: .regularTab(tabID),
                in: windowState
            )?.spaceId
        }.first ?? fallback
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
