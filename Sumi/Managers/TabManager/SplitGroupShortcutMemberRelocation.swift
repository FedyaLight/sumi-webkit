import Foundation
import SumiDomain

/// Relocates one durable shortcut while publishing the exact replacement
/// topology that owns it. Neither half can commit independently.
@MainActor
final class SplitGroupShortcutMemberRelocation {
    private let ordering: SplitGroupSidebarOrderingService
    private let mutations: SplitGroupMutationService
    private let launcherPlacement: ShortcutSplitLauncherPlacementService

    init(
        ordering: SplitGroupSidebarOrderingService,
        mutations: SplitGroupMutationService,
        launcherPlacement: ShortcutSplitLauncherPlacementService
    ) {
        self.ordering = ordering
        self.mutations = mutations
        self.launcherPlacement = launcherPlacement
    }

    func move(
        _ memberID: SplitMemberID,
        into targetContainer: SplitGroupContainer,
        expectedGroups: [SplitGroup],
        replacementGroups: [SplitGroup]
    ) -> Bool {
        guard ordering.groupsSnapshot == expectedGroups,
              let destination = destination(for: targetContainer),
              let move = launcherPlacement.prepareMove(
                  for: memberID,
                  to: destination
              ) else {
            return false
        }
        return mutations.replaceAllAtomically(
            expected: expectedGroups,
            with: replacementGroups,
            applying: { move.applyAndCommit() }
        )
    }

    private func destination(
        for container: SplitGroupContainer
    ) -> ShortcutSplitLauncherDestination? {
        switch container {
        case .regularTabs:
            return nil
        case .essentialSidebar(let profileID, let index):
            guard let profileID else { return nil }
            return ShortcutSplitLauncherDestination(
                role: .essential,
                profileId: profileID,
                spaceId: nil,
                folderId: nil,
                index: index ?? 0,
                opensFolder: false
            )
        case .shortcutSidebar(let spaceID, _, let folderID, let index):
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: folderID,
                index: index ?? 0,
                opensFolder: false
            )
        }
    }
}
