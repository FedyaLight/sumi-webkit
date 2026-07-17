import Foundation
import SumiDomain

/// Dissolves one exact split group. Shortcut launcher restoration and durable
/// group removal share one structural transaction; every presenting window is
/// reconciled only after that commit succeeds.
@MainActor
final class SplitGroupDissolutionService {
    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let presentations: WindowSplitPresentationSynchronizer

    init(
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        presentations: WindowSplitPresentationSynchronizer
    ) {
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.launcherPlacement = launcherPlacement
        self.presentations = presentations
    }

    @discardableResult
    func dissolve(
        _ group: SumiDomain.SplitGroup,
        standaloneMembers: [UUID: SplitMemberID] = [:]
    ) -> Bool {
        guard splitGroups.group(id: group.id) == group,
              let restorations = launcherPlacement.prepareRestorations(
                  for: group.members
                  ), mutations.removeAtomically(
                  group,
                  applying: {
                      restorations.applyAndCommit()
                  }
              ) else {
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
