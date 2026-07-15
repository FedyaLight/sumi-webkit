@MainActor
final class RegularTabShortcutDisplayedCommitter {
    private let structure: RegularTabShortcutCommitStructurePreparer
    private let transition: DisplayedTabShortcutConversionCommitter
    private let terminal: RegularTabShortcutTerminalEffectsFactory
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        structure: RegularTabShortcutCommitStructurePreparer,
        transition: DisplayedTabShortcutConversionCommitter,
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
        authorization: AuthorizedDisplayedTabShortcutConversion,
        presentation: RegularTabShortcutSplitPresentationPreparation?
    ) -> RegularTabShortcutConversionAcceptance? {
        var pendingPresentation: PreparedWindowSplitPresentationSettlement?
        defer { _ = pendingPresentation?.cancelPrepared() }
        guard let sidebarPreflight = commitStructure.sidebarPreparation
            .preflightBindingContribution() else { return nil }
        let builder = sidebarPreflight.builder
            ?? transition.beginBindingBatch(
                using: authorization.plan.runtimeAttachment
            )
        guard builder.matches(authorization.plan.runtimeAttachment) else {
            return nil
        }
        guard let prepared = structure.prepare(
            candidate,
            structure: commitStructure
        ) else { return nil }
        guard let bindingPreflight = transition.preflightBinding(
            to: prepared.insertion.insertedPin,
            using: authorization,
            builder: builder
        ) else {
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        guard let sidebar = structure.prepareSidebar(
            sidebarPreflight,
            insertion: prepared.insertion,
            builder: builder
        ) else {
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        guard let binding = bindingPreflight.prepareResidences(
            for: prepared.insertion.insertedPin
        ) else {
            _ = sidebar.rollbackBeforeExecution()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        if let presentation {
            guard let preparedPresentation = presentation.prepare(
                for: prepared.insertion,
                residenceContribution: binding.presentationContribution
            ) else {
                _ = binding.cancelPreparedResidences()
                _ = sidebar.rollbackBeforeExecution()
                _ = prepared.durable.cancelPrepared()
                return nil
            }
            pendingPresentation = preparedPresentation
        }
        if let presentation = pendingPresentation,
           sidebar.admitPresentationIdentity(to: presentation) == false {
            _ = binding.cancelPreparedResidences()
            _ = sidebar.rollbackBeforeExecution()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        guard let runtime = transition.prepareRuntime(
            binding,
            transition: prepared.transition,
            using: authorization
        ) else {
            _ = binding.cancelPreparedResidences()
            _ = sidebar.rollbackBeforeExecution()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        let preparation = sidebar.prepareComposedTransaction(
            additional: binding.contribution,
            windows: [
                runtime.windows,
                pendingPresentation?.windowContribution ?? .empty,
            ]
        )
        guard case .prepared(
            let model,
            let profiles,
            let targetWindowStates
        ) = preparation else {
            _ = runtime.cancelPrepared()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        if let presentation = pendingPresentation,
           prepared.durable.admitPresentation(
               presentation,
               windowStates: targetWindowStates
           ) == false {
            _ = model.cancelPrepared()
            _ = runtime.cancelPrepared()
            _ = prepared.durable.cancelPrepared()
            return nil
        }
        pendingPresentation = nil
        let aggregate = DisplayedTabShortcutBindingAggregateTransaction(
            binding: model,
            runtime: runtime,
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
