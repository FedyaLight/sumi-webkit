import Foundation
import SumiDomain

struct TabShortcutPinDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
    let opensFolder: Bool
}

/// Narrow command surface for regular-tab conversion. Preparation, replacement
/// validation and transactional commit have independent concrete services.
@MainActor
final class RegularTabShortcutConversionService {
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
        _ tab: Tab,
        preferredWindowId: UUID? = nil
    ) -> TabShortcutConversionPreparation {
        candidates.prepare(tab, preferredWindowID: preferredWindowId)
    }

    func prepareShortcutSidebarDrop(
        _ tab: Tab,
        into targetGroup: SumiDomain.SplitGroup,
        preferredWindowId: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        sidebarCandidates.prepare(
            tab: tab,
            targetGroup: targetGroup,
            preferredWindowID: preferredWindowId
        )
    }

    @discardableResult
    func commitShortcutSidebarDrop(
        _ prepared: PreparedRegularTabShortcutSidebarDrop,
        replacingSplitGroupsWith replacement: [SumiDomain.SplitGroup],
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

    @discardableResult
    func convert(
        _ tab: Tab,
        destination: TabShortcutPinDestination,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        commit(
            tab,
            preparation: prepare(tab, preferredWindowId: preferredWindowId),
            destination: destination
        )?.canonicalPin
    }

    @discardableResult
    func accept(
        _ tab: Tab,
        destination: TabShortcutPinDestination,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        commit(
            tab,
            preparation: prepare(tab, preferredWindowId: preferredWindowId),
            destination: destination
        ) != nil
    }

    @discardableResult
    func commit(
        _ tab: Tab,
        preparation: TabShortcutConversionPreparation,
        destination: TabShortcutPinDestination
    ) -> RegularTabShortcutConversionAcceptance? {
        guard let candidate = candidates.candidate(
            for: tab,
            preparation: preparation,
            destination: destination
        ), let authorization = candidates.authorization(for: candidate) else {
            return nil
        }
        return transaction.commit(candidate, authorization: authorization)
    }
}
