import Foundation
import SumiDomain

/// Narrow command surface for regular-tab conversion. Preparation, replacement
/// validation and transactional commit have independent concrete services.
@MainActor
final class RegularTabShortcutConversionService {
    private let candidates: RegularTabShortcutCandidatePreparer
    private let sidebar: RegularTabShortcutSidebarConversionService
    private let transaction: RegularTabShortcutCommitTransaction

    init(
        candidates: RegularTabShortcutCandidatePreparer,
        sidebar: RegularTabShortcutSidebarConversionService,
        transaction: RegularTabShortcutCommitTransaction
    ) {
        self.candidates = candidates
        self.sidebar = sidebar
        self.transaction = transaction
    }

    func prepare(
        _ tab: Tab,
        preferredWindowId: UUID? = nil
    ) -> TabShortcutConversionPreparation {
        candidates.prepare(tab, preferredWindowID: preferredWindowId)
    }

    func prepareSplitGroupMoveMember(
        _ tab: Tab,
        sourceGroupID: UUID,
        preferredWindowId: UUID?
    ) -> TabShortcutConversionPreparation {
        candidates.prepareSplitGroupMoveMember(
            tab,
            sourceGroupID: sourceGroupID,
            preferredWindowID: preferredWindowId
        )
    }

    func prepareShortcutSidebarDrop(
        _ tab: Tab,
        into targetGroup: SumiDomain.SplitGroup,
        preferredWindowId: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        sidebar.prepare(
            tab: tab,
            targetGroup: targetGroup,
            preferredWindowID: preferredWindowId
        )
    }

    func prepareShortcutSidebarDrop(
        _ tab: Tab,
        onto standaloneTargetPin: ShortcutPin,
        target: SplitDropTarget,
        preferredWindowId: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        sidebar.prepare(
            tab: tab,
            standaloneTargetPin: standaloneTargetPin,
            target: target,
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
        sidebar.commit(
            prepared,
            replacement: replacement,
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
