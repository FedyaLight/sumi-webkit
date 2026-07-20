import Foundation
import SumiDomain

@MainActor
final class SplitLayoutTopologyTransaction {
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let regularTabs: RegularTabCollectionOwner

    init(
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        regularTabs: RegularTabCollectionOwner
    ) {
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.regularTabs = regularTabs
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
        guard replacement != expected,
              mutations.replaceAll(expected: expected, with: replacement)
        else { return nil }
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

    init(
        topology: SplitLayoutTopologyTransaction,
        query: WindowSplitQuery,
        weightMutations: SplitLayoutWeightMutationService,
        presentations: WindowSplitPresentationSynchronizer,
        dissolution: SplitGroupDissolutionService
    ) {
        self.topology = topology
        self.query = query
        self.weightMutations = weightMutations
        self.presentations = presentations
        self.dissolution = dissolution
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
              setLayoutKind(layoutKind, for: group, in: windowID) else {
            return
        }
    }

    @discardableResult
    func setLayoutKind(
        _ layoutKind: SplitLayoutKind,
        groupID: UUID,
        in windowID: UUID
    ) -> Bool {
        guard let group = query.group(id: groupID) else { return false }
        return setLayoutKind(layoutKind, for: group, in: windowID)
    }

    private func setLayoutKind(
        _ layoutKind: SplitLayoutKind,
        for group: SumiDomain.SplitGroup,
        in windowID: UUID
    ) -> Bool {
        guard
              let replacement = group.changingLayout(to: layoutKind),
              replacement != group,
              topology.replace(
                  group,
                  with: replacement
              ) else {
            return false
        }
        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id]
        )
        return true
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

    func unsplit(groupID: UUID) {
        guard let group = query.group(id: groupID) else { return }
        _ = dissolution.dissolve(group)
    }

    func separate(
        _ memberID: SplitMemberID,
        from groupID: UUID,
        in windowState: BrowserWindowState
    ) {
        guard let group = query.group(id: groupID),
              group.contains(memberID) else { return }
        commitSeparation(memberID, from: group, in: windowState)
    }

    func expand(tabID: UUID, in windowState: BrowserWindowState) {
        guard let presentation = query.resolution(
                  in: windowState.id
              ).presentation,
              let memberID = presentation.memberID(for: tabID) else {
            return
        }
        commitSeparation(memberID, from: presentation.group, in: windowState)
    }

    private func commitSeparation(
        _ memberID: SplitMemberID,
        from group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) {
        if case .regularTab(let regularTabID) = memberID,
           !topology.containsRegularTab(regularTabID) {
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
