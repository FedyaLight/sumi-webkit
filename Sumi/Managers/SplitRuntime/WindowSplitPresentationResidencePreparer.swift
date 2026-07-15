@MainActor
enum WindowSplitPresentationActivationSource {
    case canonical
    case displayedBinding(
        ShortcutPresentationCatalogInsertionPreview,
        DisplayedShortcutResidenceContribution
    )
}

@MainActor
struct WindowSplitPresentationResidencePreparer {
    func prepare(
        source: WindowSplitPresentationActivationSource,
        requests: [ShortcutPresentationActivationService.Request],
        activation: ShortcutPresentationActivationService
    ) -> WindowSplitPresentationResidenceTransaction? {
        switch source {
        case .canonical:
            return activation.prepareActivation(requests).map(
                WindowSplitPresentationResidenceTransaction.activation
            )
        case .displayedBinding(let preview, let contribution):
            guard let prepared = contribution.prepare(
                requests,
                preview: preview
            ), let owned = activation.prepareActivation(
                prepared.remainder,
                preview: preview
            ), let transaction =
                DisplayedWindowSplitPresentationResidenceTransaction(
                    activation: owned,
                    contribution: prepared
                ) else { return nil }
            return .displayedBinding(transaction)
        }
    }
}
