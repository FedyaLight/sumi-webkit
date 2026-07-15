@MainActor
final class RegularTabShortcutDetachedCommitter {
    private let structure: RegularTabShortcutCommitStructurePreparer
    private let transition: DetachedTabShortcutConverter
    private let terminal: RegularTabShortcutTerminalEffectsFactory
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        structure: RegularTabShortcutCommitStructurePreparer,
        transition: DetachedTabShortcutConverter,
        terminal: RegularTabShortcutTerminalEffectsFactory,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.structure = structure
        self.transition = transition
        self.terminal = terminal
        self.structuralLookup = structuralLookup
    }

    func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        structure commitStructure: RegularTabShortcutCommitStructure,
        authorization: AuthorizedDetachedTabShortcutConversion,
        presentation: RegularTabShortcutSplitPresentationPreparation?
    ) -> RegularTabShortcutConversionAcceptance? {
        guard presentation == nil else { return nil }
        guard let sidebarPreflight = commitStructure.sidebarPreparation
            .preflightBindingContribution() else { return nil }
        let builder = sidebarPreflight.builder
            ?? transition.beginBindingBatch(
                using: authorization.runtimeAttachment
            )
        guard builder.matches(authorization.runtimeAttachment) else {
            return nil
        }
        guard let prepared = structure.prepare(
            candidate,
            structure: commitStructure
        ) else { return nil }
        guard let source = transition.prepare(
            transition: prepared.transition,
            using: authorization
        ) else {
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        guard let sidebar = structure.prepareSidebar(
            sidebarPreflight,
            insertion: prepared.insertion,
            builder: builder
        ) else {
            _ = source.runtime.cancelPrepared()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        guard sidebar.binding != nil else {
            _ = source.runtime.cancelPrepared()
            _ = sidebar.rollbackBeforeExecution()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        let preparation = sidebar.prepareComposedTransaction(
            additional: nil,
            windows: [
                source.windows,
            ]
        )
        guard case .prepared(
            let model,
            let profiles,
            _
        ) = preparation else {
            _ = source.runtime.cancelPrepared()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        let aggregate = DetachedTabShortcutBindingAggregateTransaction(
            binding: model,
            runtime: source.runtime,
            durable: prepared.durable,
            terminal: terminal.make(destination: candidate.destination),
            structuralLookup: structuralLookup
        )
        guard profiles.isCurrent(for: aggregate) else {
            _ = aggregate.cancelPrepared()
            return nil
        }
        terminal.requestFolderCommit(for: sidebar)
        switch profiles.execute(bindingModel: aggregate) {
        case .committed:
            guard let pin = structure.committedPin(for: prepared) else {
                preconditionFailure("Committed shortcut has no canonical pin")
            }
            return RegularTabShortcutConversionAcceptance(
                pinID: pin.id,
                disposition: .syncCommitted(pin)
            )
        case .pipelineOwned:
            return RegularTabShortcutConversionAcceptance(
                pinID: prepared.insertion.insertedPin.id,
                disposition: .pipelineOwned
            )
        case .rejectedUnstaged, .rejectedSettled, .conflicted:
            return nil
        }
    }
}
