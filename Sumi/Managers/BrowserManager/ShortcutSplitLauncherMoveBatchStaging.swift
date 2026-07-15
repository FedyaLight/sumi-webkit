import Foundation

@MainActor
final class ShortcutSplitLauncherMoveBatchStaging:
    ShortcutSplitLauncherMoveBatchPreparing {
    let catalog: ShortcutSplitLauncherCatalogTransaction
    let bindingStaging: ShortcutSplitLauncherBindingStaging
    let residenceMutations: LiveShortcutResidenceMutationStaging
    let structuralMutations: TabStructuralCollectionMutationOwner
    let structuralLookup: TabStructuralLookupCoordinator

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        bindingStaging: ShortcutSplitLauncherBindingStaging,
        residenceMutations: LiveShortcutResidenceMutationStaging,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.catalog = catalog
        self.bindingStaging = bindingStaging
        self.residenceMutations = residenceMutations
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        guard let preview = catalog.preview(pin, destination: destination) else {
            return false
        }
        return bindingStaging.admission(for: preview) != nil
    }

    func prepare(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        guard let preflight = preflightBindingContribution(restorations),
              let contribution = prepareContribution(
                  preflight,
                  terminalRestorations: restorations
              ) else { return nil }
        return makeParticipant(from: contribution)
    }

    func prepareForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)? {
        guard let contribution =
            prepareBindingContributionForComposedResidenceAggregate(
                restorations,
                bindingMode: bindingMode
            ) else { return nil }
        return ShortcutSplitLauncherComposedMoveBatchReceipt(
            contribution: contribution,
            structuralMutations: structuralMutations,
            structuralLookup: structuralLookup
        )
    }

    func prepareBindingContributionForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingContribution? {
        prepareBindingContributionForComposedResidenceAggregate(
            restorations,
            bindingMode: .preservingLiveBindings
        )
    }

    private func prepareBindingContributionForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> ShortcutSplitLauncherBindingContribution? {
        guard let preflight = preflightBindingContribution(
            restorations,
            bindingMode: bindingMode
        ) else {
            return nil
        }
        let contribution = prepareContribution(
            preflight,
            terminalRestorations: restorations
        )
        return contribution
    }

    private func makeParticipant(
        from contribution: ShortcutSplitLauncherBindingContribution
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        guard case .prepared(let model, let profiles, _) = contribution
            .prepareComposedTransaction(windows: [.empty]) else { return nil }
        let bindingModel = ShortcutSplitLauncherBindingAggregateTransaction(
            model: model,
            structuralMutations: structuralMutations,
            structuralLookup: structuralLookup
        )
        return ShortcutSplitLauncherMoveBatchReceipt(
            bindingModel: bindingModel,
            profiles: profiles,
            folders: contribution.folders
        )
    }
}
