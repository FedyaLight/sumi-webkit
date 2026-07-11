import Foundation
import SumiDomain

struct CommittedRegularTabShortcutSidebarDrop {
    let effect: SplitDropCommitEffect
}

/// Executes the special identity-changing split drop. All layout values are
/// derived from the candidate's exact snapshot before pin insertion.
@MainActor
final class RegularTabShortcutSidebarDropTransaction {
    private let tabManager: @MainActor () -> TabManager?
    private let launcherPlacement: ShortcutSplitLauncherPlacementService

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        launcherPlacement: ShortcutSplitLauncherPlacementService
    ) {
        self.tabManager = tabManager
        self.launcherPlacement = launcherPlacement
    }

    func commit(
        tab: Tab,
        sourceMemberID: SplitMemberID,
        targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> CommittedRegularTabShortcutSidebarDrop? {
        guard let tabManager = tabManager(),
              let prepared = tabManager.regularTabShortcutConversion
                .prepareShortcutSidebarDrop(
                    tab,
                    into: targetGroup,
                    preferredWindowId: windowState.id
                ),
              let preparedTarget = prepared.expectedSplitGroups.first(
                  where: { $0 == targetGroup }
              ),
              let updatedTree = SplitDropGroupAlgebra.resolvedTree(
                  for: prepared.member,
                  in: preparedTarget,
                  target: target
              ),
              let replacementTarget = preparedTarget.replacingLayoutTree(
                  with: updatedTree
              ) else {
            return nil
        }

        let sourceGroup = prepared.expectedSplitGroups.first {
            $0.contains(sourceMemberID)
        }
        let replacement = SplitDropGroupAlgebra.replacingGroups(
            prepared.expectedSplitGroups,
            sourceGroup: sourceGroup,
            movingMemberID: sourceMemberID,
            targetGroup: preparedTarget,
            replacementTarget: replacementTarget
        )
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: windowState.id,
            sourceGroup: sourceGroup,
            targetGroup: preparedTarget,
            committedTargetGroupID: replacementTarget.id,
            movingMemberID: sourceMemberID,
            activatedMemberID: prepared.member.memberID,
            replacementGroups: replacement
        )
        guard let restorations = launcherPlacement.prepareRestorations(
            for: effect.releasedMembers
        ) else { return nil }
        guard tabManager.regularTabShortcutConversion
            .commitShortcutSidebarDrop(
                prepared,
                replacingSplitGroupsWith: replacement,
                applyingSplitSideEffect: { [launcherPlacement] in
                    launcherPlacement.apply(restorations)
                }
            ) != nil else {
            return nil
        }
        return CommittedRegularTabShortcutSidebarDrop(
            effect: effect
        )
    }
}
