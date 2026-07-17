import Foundation
import SumiDomain

@MainActor
final class SplitShortcutMemberRestoreService {
    private let preparation: SplitShortcutMemberRestorePreparationService
    private let splitMutations: SplitGroupMutationService
    private let shortcutRetirement: ShortcutLiveTabRetirementService
    private let publication: SplitShortcutMemberRestorePublication

    init(
        preparation: SplitShortcutMemberRestorePreparationService,
        splitMutations: SplitGroupMutationService,
        shortcutRetirement: ShortcutLiveTabRetirementService,
        publication: SplitShortcutMemberRestorePublication
    ) {
        self.preparation = preparation
        self.splitMutations = splitMutations
        self.shortcutRetirement = shortcutRetirement
        self.publication = publication
    }

    @discardableResult
    func restoreShortcutSplitMember(
        _ memberID: SplitMemberID,
        from group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) -> Bool {
        guard let prepared = preparation.prepare(
            memberID,
            from: group,
            in: windowState,
            preserveLiveInstance: preserveLiveInstance
        ) else { return false }

        guard let presentation = publication.prepare(
            prepared,
            memberID: memberID,
            sourceGroup: group,
            windowState: windowState,
            preserveLiveInstance: preserveLiveInstance
        ) else { return false }
        guard let topology = splitMutations.prepareReplaceAll(
            expected: prepared.sourceGroups,
            with: prepared.replacementGroups
        ) else { return false }

        let retirement: ReversibleShortcutLiveTabRetirement?
        if let retiringPinID = prepared.retiringPinID {
            guard let prepared = shortcutRetirement
                .prepareReversibleRetirement(
                    pinId: retiringPinID,
                    in: windowState.id
                ) else {
                _ = presentation.cancelPrepared()
                topology.rollback()
                return false
            }
            retirement = prepared
        } else {
            retirement = nil
        }
        let bindingMode: ShortcutSplitLauncherComposedBindingMode
        if let retirement {
            guard let exclusion = retirement.bindingExclusion else {
                _ = presentation.cancelPrepared()
                _ = retirement.cancelPrepared()
                topology.rollback()
                return false
            }
            bindingMode = .consumingExactRetirement(exclusion)
        } else {
            bindingMode = .preservingLiveBindings
        }
        guard let move = prepared.launcher.applyForComposedResidenceAggregate(
            bindingMode: bindingMode
        ) else {
            _ = presentation.cancelPrepared()
            _ = retirement?.cancelPrepared()
            topology.rollback()
            return false
        }
        guard move.admitPresentationIdentity(to: presentation) else {
            _ = move.cancelPrepared()
            _ = presentation.cancelPrepared()
            _ = retirement?.cancelPrepared()
            topology.rollback()
            return false
        }
        guard let outcome = publication.execute(
            move,
            presentation: presentation,
            retirement: retirement,
            topology: topology,
            retirementService: shortcutRetirement
        ) else { return false }
        return outcome.wasAccepted
    }
}
