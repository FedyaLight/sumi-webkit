import Foundation
import SumiDomain

/// Prepares and commits the identity-changing regular-tab sidebar drop.
@MainActor
final class RegularTabShortcutSidebarConversionService {
    private let candidates: RegularTabShortcutCandidatePreparer
    private let sidebarCandidates: RegularTabShortcutSidebarCandidatePreparer
    private let replacementValidator: ShortcutSidebarDropReplacementValidator
    private let transaction: RegularTabShortcutCommitTransaction

    init(
        candidates: RegularTabShortcutCandidatePreparer,
        sidebarCandidates: RegularTabShortcutSidebarCandidatePreparer,
        replacementValidator: ShortcutSidebarDropReplacementValidator,
        transaction: RegularTabShortcutCommitTransaction
    ) {
        self.candidates = candidates
        self.sidebarCandidates = sidebarCandidates
        self.replacementValidator = replacementValidator
        self.transaction = transaction
    }

    func prepare(
        tab: Tab,
        targetGroup: SumiDomain.SplitGroup,
        preferredWindowID: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        sidebarCandidates.prepare(
            tab: tab,
            targetGroup: targetGroup,
            preferredWindowID: preferredWindowID
        )
    }

    func prepare(
        tab: Tab,
        standaloneTargetPin: ShortcutPin,
        target: SplitDropTarget,
        preferredWindowID: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        sidebarCandidates.prepare(
            tab: tab,
            standaloneTargetPin: standaloneTargetPin,
            target: target,
            preferredWindowID: preferredWindowID
        )
    }

    func commit(
        _ prepared: PreparedRegularTabShortcutSidebarDrop,
        replacement: [SumiDomain.SplitGroup],
        sidebarMutation: RegularTabShortcutSidebarMutationPreparation,
        presentation: RegularTabShortcutSplitPresentationPreparation
    ) -> RegularTabShortcutConversionAcceptance? {
        guard replacementValidator.accepts(replacement, for: prepared),
              let authorization = candidates.authorization(
                  for: prepared.conversion
              ) else { return nil }
        return transaction.commit(
            prepared,
            replacement: replacement,
            authorization: authorization,
            sidebarMutation: sidebarMutation,
            presentation: presentation
        )
    }
}
