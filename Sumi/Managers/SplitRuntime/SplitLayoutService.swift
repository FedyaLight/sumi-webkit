import Foundation
import SumiDomain

@MainActor
final class SplitLayoutTopologyTransaction {
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let regularTabs: RegularTabCollectionOwner
    private let launcherPlacement: ShortcutSplitLauncherPlacementService

    init(
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        regularTabs: RegularTabCollectionOwner,
        launcherPlacement: ShortcutSplitLauncherPlacementService
    ) {
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.regularTabs = regularTabs
        self.launcherPlacement = launcherPlacement
    }

    func replace(
        _ group: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup
    ) -> Bool {
        mutations.replace(group, with: replacement)
    }

    func containsGroup(_ groupID: UUID) -> Bool {
        splitGroups.group(id: groupID) != nil
    }

    func containsRegularTab(_ tabID: UUID) -> Bool {
        regularTabs.tab(for: tabID) != nil
    }

    func removeClosedRegularTabs(
        _ tabIDs: Set<UUID>
    ) -> [SumiDomain.SplitGroup]? {
        let memberIDs = Set(tabIDs.map(SplitMemberID.regularTab))
        let expected = splitGroups.groups
        let replacement = expected.compactMap { group in
            memberIDs.reduce(Optional(group)) { candidate, memberID in
                guard let candidate, candidate.contains(memberID) else {
                    return candidate
                }
                return candidate.removingMember(memberID)
            }
        }
        let changedGroups = expected.filter { previous in
            replacement.first(where: { $0.id == previous.id }) != previous
        }
        let remainingMemberIDs = Set(replacement.flatMap(\.memberIDs))
        let releasedShortcuts = changedGroups.flatMap(\.members).filter {
            guard case .shortcutPin = $0.memberID else { return false }
            return !remainingMemberIDs.contains($0.memberID)
        }
        guard let restorations = launcherPlacement.prepareRestorations(
            for: releasedShortcuts
        ), replacement != expected,
           mutations.replaceAllAtomically(
               expected: expected,
               with: replacement,
               applying: { restorations.applyAndCommit() }
           ) else { return nil }
        return changedGroups
    }
}

/// Durable split-layout lifecycle. Every structural change is committed
/// against an exact snapshot; window selection is reconciled only afterward.
@MainActor
final class SplitLayoutService {
    private let topology: SplitLayoutTopologyTransaction
    private let query: WindowSplitQuery
    private let weightMutations: SplitLayoutWeightMutationService
    private let presentations: WindowSplitPresentationSynchronizer
    private let dissolution: SplitGroupDissolutionService
    private let restoreShortcutMember: @MainActor (
        SplitMemberID,
        SumiDomain.SplitGroup,
        BrowserWindowState
    ) -> Bool

    init(
        topology: SplitLayoutTopologyTransaction,
        query: WindowSplitQuery,
        weightMutations: SplitLayoutWeightMutationService,
        presentations: WindowSplitPresentationSynchronizer,
        dissolution: SplitGroupDissolutionService,
        restoreShortcutMember: @escaping @MainActor (
            SplitMemberID,
            SumiDomain.SplitGroup,
            BrowserWindowState
        ) -> Bool
    ) {
        self.topology = topology
        self.query = query
        self.weightMutations = weightMutations
        self.presentations = presentations
        self.dissolution = dissolution
        self.restoreShortcutMember = restoreShortcutMember
    }

    func updateWeights(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double],
        in windowID: UUID
    ) {
        guard weightMutations.update(
            expectedGroup: expectedGroup,
            path: path,
            weights: weights
        ) else {
            return
        }
        presentations.refreshPresentations(for: [expectedGroup.id])
    }

    func setLayoutKind(_ layoutKind: SplitLayoutKind, in windowID: UUID) {
        guard let group = query.group(in: windowID),
              let replacement = group.changingLayout(to: layoutKind),
              replacement != group,
              topology.replace(
                  group,
                  with: replacement
              ) else {
            return
        }
        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id]
        )
    }

    func stageClosedRegularTabs(
        _ tabIDs: Set<UUID>
    ) -> PreparedSplitTabClosureSettlement? {
        guard !tabIDs.isEmpty else { return nil }
        guard let changedGroups = topology.removeClosedRegularTabs(tabIDs)
        else { return nil }
        return PreparedSplitTabClosureSettlement(
            presentations: presentations,
            previousGroups: changedGroups,
            affectedGroupIDs: Set(changedGroups.map(\.id))
        )
    }

    func unsplit(in windowState: BrowserWindowState) {
        guard let group = query.group(in: windowState.id) else {
            return
        }
        _ = dissolution.dissolve(group)
    }

    func expand(tabID: UUID, in windowState: BrowserWindowState) {
        guard let presentation = query.resolution(
                  in: windowState.id
              ).presentation,
              let memberID = presentation.memberID(for: tabID) else {
            return
        }
        let group = presentation.group
        if case .shortcutPin = memberID {
            _ = restoreShortcutMember(memberID, group, windowState)
            return
        }
        guard case .regularTab(let regularTabID) = memberID,
              topology.containsRegularTab(regularTabID) else {
            return
        }

        let didCommit: Bool
        if let replacement = group.removingMember(memberID) {
            didCommit = topology.replace(
                group,
                with: replacement
            )
        } else {
            didCommit = dissolution.dissolve(
                group,
                standaloneMembers: [windowState.id: memberID]
            )
        }
        guard didCommit else { return }
        guard topology.containsGroup(group.id) else {
            return
        }
        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id],
            standaloneMembers: [windowState.id: memberID]
        )
    }
}
