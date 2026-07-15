import SumiDomain

@MainActor
final class RegularTabShortcutCommitTransaction {
    private let displayed: RegularTabShortcutDisplayedCommitter
    private let detached: RegularTabShortcutDetachedCommitter

    init(
        displayed: RegularTabShortcutDisplayedCommitter,
        detached: RegularTabShortcutDetachedCommitter
    ) {
        self.displayed = displayed
        self.detached = detached
    }

    func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        authorization: AuthorizedTabShortcutConversion
    ) -> RegularTabShortcutConversionAcceptance? {
        commit(
            candidate,
            structure: .sourceReplacement,
            authorization: authorization
        )
    }

    func commit(
        _ prepared: PreparedRegularTabShortcutSidebarDrop,
        replacement: [SplitGroup],
        authorization: AuthorizedTabShortcutConversion,
        sidebarMutation: RegularTabShortcutSidebarMutationPreparation,
        presentation: RegularTabShortcutSplitPresentationPreparation
    ) -> RegularTabShortcutConversionAcceptance? {
        commit(
            prepared.conversion,
            structure: .sidebar(
                prepared,
                replacement,
                sidebarMutation
            ),
            authorization: authorization,
            presentation: presentation
        )
    }

    private func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        structure: RegularTabShortcutCommitStructure,
        authorization: AuthorizedTabShortcutConversion,
        presentation: RegularTabShortcutSplitPresentationPreparation? = nil
    ) -> RegularTabShortcutConversionAcceptance? {
        switch authorization {
        case .displayed(let value):
            return displayed.commit(
                candidate,
                structure: structure,
                authorization: value,
                presentation: presentation
            )
        case .detached(let value):
            return detached.commit(
                candidate,
                structure: structure,
                authorization: value,
                presentation: presentation
            )
        }
    }
}
