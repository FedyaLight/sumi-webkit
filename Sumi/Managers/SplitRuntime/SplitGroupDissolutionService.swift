import Foundation
import SumiDomain

/// Dissolves one exact split group. Members remain in their canonical tab or
/// shortcut collections; only the grouping projection is removed.
@MainActor
final class SplitGroupDissolutionService {
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let presentations: WindowSplitPresentationSynchronizer

    init(
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        presentations: WindowSplitPresentationSynchronizer
    ) {
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.presentations = presentations
    }

    @discardableResult
    func dissolve(
        _ group: SumiDomain.SplitGroup,
        standaloneMembers: [UUID: SplitMemberID] = [:]
    ) -> Bool {
        guard splitGroups.group(id: group.id) == group,
              mutations.remove(group) else {
            return false
        }

        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id],
            standaloneMembers: standaloneMembers
        )
        return true
    }
}
