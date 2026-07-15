import Foundation
import SumiDomain

/// Dissolves one exact split group. Shortcut launcher restoration and durable
/// group removal share one structural transaction; every presenting window is
/// reconciled only after that commit succeeds.
@MainActor
final class SplitGroupDissolutionService {
    private let tabManager: @MainActor () -> TabManager?
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let presentations: WindowSplitPresentationSynchronizer

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        presentations: WindowSplitPresentationSynchronizer
    ) {
        self.tabManager = tabManager
        self.launcherPlacement = launcherPlacement
        self.presentations = presentations
    }

    @discardableResult
    func dissolve(
        _ group: SumiDomain.SplitGroup,
        standaloneMembers: [UUID: SplitMemberID] = [:]
    ) -> Bool {
        guard let tabManager = tabManager(),
              tabManager.splitGroupStore.group(id: group.id) == group,
              let restorations = launcherPlacement.prepareRestorations(
                  for: group.members
                  ), tabManager.splitGroupMutations.removeAtomically(
                  group,
                  applying: { [launcherPlacement] in
                      launcherPlacement.applyAndCommit(restorations)
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
