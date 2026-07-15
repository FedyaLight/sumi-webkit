import Foundation
import SumiDomain

/// Executes the special identity-changing split drop. All layout values are
/// derived from the candidate's exact snapshot before pin insertion.
@MainActor
final class RegularTabShortcutSidebarDropTransaction {
    private let tabManager: @MainActor () -> TabManager?
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let presentations: any SplitDropPresentationReconciling

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        presentations: any SplitDropPresentationReconciling
    ) {
        self.tabManager = tabManager
        self.launcherPlacement = launcherPlacement
        self.presentations = presentations
    }

    func commit(
        tab: Tab,
        sourceMemberID: SplitMemberID,
        targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
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
            return false
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
        guard let sidebarMutation = launcherPlacement.prepareSidebarMutation(
            for: effect.releasedMembers
        ) else { return false }
        let presentation = RegularTabShortcutSplitPresentationPreparation(
            presentations: presentations,
            effect: effect,
            sourceGroups: prepared.expectedSplitGroups,
            replacementGroups: replacement,
            requiredWindow: windowState
        )
        guard tabManager.regularTabShortcutConversion
            .commitShortcutSidebarDrop(
                prepared,
                replacingSplitGroupsWith: replacement,
                sidebarMutation: sidebarMutation,
                presentation: presentation
            ) != nil else {
            return false
        }
        return true
    }
}
