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
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        guard let preflight = preflightBindingContribution(preparedMoves),
              let contribution = prepareContribution(
                  preflight,
                  terminalMoves: preparedMoves
              ) else { return nil }
        return makeParticipant(from: contribution)
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
