import Foundation
import SumiDomain

/// Dissolves one exact split group. Members remain in their canonical tab or
/// shortcut collections; only the grouping projection is removed.
@MainActor
final class SplitGroupDissolutionService {
    private let splitGroups: SplitGroupStore
    private let releaseOrdering: SplitGroupReleaseOrderingService
    private let presentations: WindowSplitPresentationSynchronizer

    init(
        splitGroups: SplitGroupStore,
        releaseOrdering: SplitGroupReleaseOrderingService,
        presentations: WindowSplitPresentationSynchronizer
    ) {
        self.splitGroups = splitGroups
        self.releaseOrdering = releaseOrdering
        self.presentations = presentations
    }

    func replace(
        _ group: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup
    ) -> Bool {
        guard splitGroups.group(id: group.id) == group else { return false }
        return releaseOrdering.commit(group, replacingWith: replacement)
    }

    @discardableResult
    func dissolve(
        _ group: SumiDomain.SplitGroup,
        standaloneMembers: [UUID: SplitMemberID] = [:]
    ) -> Bool {
        guard splitGroups.group(id: group.id) == group,
              releaseOrdering.commit(group, replacingWith: nil) else {
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
