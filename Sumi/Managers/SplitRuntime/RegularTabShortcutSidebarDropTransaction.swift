import Foundation
import SumiDomain

/// Executes the special identity-changing split drop. All layout values are
/// derived from the candidate's exact snapshot before pin insertion.
@MainActor
final class RegularTabShortcutSidebarDropTransaction {
    private let conversion: RegularTabShortcutConversionService
    private let presentations: any SplitDropPresentationReconciling

    init(
        conversion: RegularTabShortcutConversionService,
        presentations: any SplitDropPresentationReconciling
    ) {
        self.conversion = conversion
        self.presentations = presentations
    }

    func commit(
        tab: Tab,
        sourceMemberID: SplitMemberID,
        targetGroup: SumiDomain.SplitGroup,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard let prepared = conversion.prepareShortcutSidebarDrop(
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
        let presentation = RegularTabShortcutSplitPresentationPreparation(
            presentations: presentations,
            effect: effect,
            sourceGroups: prepared.expectedSplitGroups,
            replacementGroups: replacement,
            requiredWindow: windowState
        )
        guard conversion.commitShortcutSidebarDrop(
                prepared,
                replacingSplitGroupsWith: replacement,
                sidebarMutation: .noChange,
                presentation: presentation
            ) != nil else {
            return false
        }
        return true
    }

    func commit(
        tab: Tab,
        sourceMemberID: SplitMemberID,
        standaloneTargetPin: ShortcutPin,
        target: SplitDropTarget,
        windowState: BrowserWindowState
    ) -> Bool {
        guard let prepared = conversion.prepareShortcutSidebarDrop(
            tab,
            onto: standaloneTargetPin,
            target: target,
            preferredWindowId: windowState.id
        ), prepared.targetGroupWasExisting == false else {
            return false
        }

        let sourceGroup = prepared.expectedSplitGroups.first {
            $0.contains(sourceMemberID)
        }
        var replacement = SplitDropGroupAlgebra.removingSourceGroup(
            sourceGroup,
            memberID: sourceMemberID,
            from: prepared.expectedSplitGroups
        )
        replacement.append(prepared.targetGroup)
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: windowState.id,
            sourceGroup: sourceGroup,
            targetGroup: nil,
            committedTargetGroupID: prepared.targetGroup.id,
            movingMemberID: sourceMemberID,
            activatedMemberID: prepared.member.memberID,
            replacementGroups: replacement
        )
        let presentation = RegularTabShortcutSplitPresentationPreparation(
            presentations: presentations,
            effect: effect,
            sourceGroups: prepared.expectedSplitGroups,
            replacementGroups: replacement,
            requiredWindow: windowState
        )
        return conversion.commitShortcutSidebarDrop(
            prepared,
            replacingSplitGroupsWith: replacement,
            sidebarMutation: .noChange,
            presentation: presentation
        ) != nil
    }
}
