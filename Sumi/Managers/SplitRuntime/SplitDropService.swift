import CoreGraphics
import Foundation
import SumiDomain

/// Commits one drag/drop intent as a single exact split-store transaction.
/// Hit testing is handled by the resolver family; this service owns only the
/// structural move and the resulting window-local selection.
@MainActor
final class SplitDropService {
    private let tabManager: @MainActor () -> TabManager?
    private let memberResolver: SplitRuntimeMemberResolver
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let placeholderReplacements: SplitPlaceholderReplacementPlanner
    private let regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction
    private let presentations: any SplitDropPresentationReconciling
    private let notifyLimit: @MainActor (BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        memberResolver: SplitRuntimeMemberResolver,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        placeholderReplacements: SplitPlaceholderReplacementPlanner,
        presentations: any SplitDropPresentationReconciling,
        notifyLimit: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.memberResolver = memberResolver
        self.launcherPlacement = launcherPlacement
        self.placeholderReplacements = placeholderReplacements
        regularShortcutSidebarDrop = RegularTabShortcutSidebarDropTransaction(
            tabManager: tabManager,
            launcherPlacement: launcherPlacement,
            presentations: presentations
        )
        self.presentations = presentations
        self.notifyLimit = notifyLimit
    }

    @discardableResult
    func drop(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard tab.representsSumiNativeSurface == false,
              let tabManager = tabManager() else {
            return false
        }
        return tabManager.structuralLookupCoordinator.withTransaction {
            commitDrop(tab, on: target, in: windowState, tabManager: tabManager)
        }
    }

    private func commitDrop(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Bool {
        let incomingID = tabManager.splitGroupMembership.memberID(for: tab)

        let sourceGroup = tabManager.splitGroupStore.group(
            containing: incomingID
        )
        let targetGroup = tabManager.splitGroupStore.group(
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
                windowState: windowState,
                tabManager: tabManager
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
                windowState: windowState,
                tabManager: tabManager
            )
        }
        if let targetGroup {
            return insert(
                incoming,
                sourceGroup: sourceGroup,
                into: targetGroup,
                target: target,
                windowState: windowState,
                tabManager: tabManager
            )
        }
        return createGroup(
            incoming,
            sourceGroup: sourceGroup,
            target: target,
            windowState: windowState,
            tabManager: tabManager
        )
    }

    func preparePlaceholderReplacement(
        with tab: Tab,
        placeholder: Tab,
        in windowState: BrowserWindowState
    ) -> (any SplitPlaceholderReplacementMutation)? {
        placeholderReplacements.prepare(
            tab: tab,
            placeholder: placeholder,
            window: windowState
        )
    }

    private func rearrange(
        _ incoming: ResolvedSplitRuntimeMember,
        in group: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState,
        tabManager: TabManager
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
        let expectedGroups = tabManager.splitGroupStore.groups
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
            effect: effect,
            tabManager: tabManager
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func insert(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState,
        tabManager: TabManager
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

        let expected = tabManager.splitGroupStore.groups
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
            effect: effect,
            tabManager: tabManager
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func createGroup(
        _ incoming: ResolvedSplitRuntimeMember,
        sourceGroup: SumiDomain.SplitGroup?,
        target: SplitDropTarget,
        windowState: BrowserWindowState,
        tabManager: TabManager
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

        let expected = tabManager.splitGroupStore.groups
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
            effect: effect,
            tabManager: tabManager
        ) else { return false }
        presentations.reconcile(effect)
        return true
    }

    private func insertRegularTabAsShortcut(
        _ tab: Tab,
        sourceMemberID: SplitMemberID,
        into targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState,
        tabManager: TabManager
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
        tabManager.structuralLookupCoordinator.flushPendingWritesForRead()
        return true
    }

    private func commit(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        effect: SplitDropCommitEffect,
        tabManager: TabManager
    ) -> Bool {
        guard let restorations = launcherPlacement.prepareRestorations(
            for: effect.releasedMembers
        ) else {
            return false
        }
        return tabManager.splitGroupMutations.replaceAllAtomically(
            expected: expected,
            with: replacement,
            applying: {
                restorations.applyAndCommit()
            }
        )
    }
}
