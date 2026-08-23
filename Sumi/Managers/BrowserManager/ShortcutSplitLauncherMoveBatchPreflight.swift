import Foundation

@MainActor
extension ShortcutSplitLauncherMoveBatchStaging {
    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        guard Set(preparedMoves.map { $0.pin.id }).count == preparedMoves.count,
              preparedMoves.allSatisfy({ catalog.isCurrent($0.pin) }) else {
            return nil
        }
        let bindingBatch = bindingStaging.beginBatch()
        let entries = preparedMoves.compactMap { preparedMove in
            guard let preview = catalog.preview(
                preparedMove.pin,
                destination: preparedMove.destination
            ) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            guard let admitted = bindingBatch.admission(for: preview) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            guard let binding = bindingBatch.prepare(
                   pin: preview,
                   admission: admitted
               ) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            return ShortcutSplitLauncherBindingPreflight.Entry(
                preparedMove: preparedMove,
                binding: binding
            )
        }
        guard entries.count == preparedMoves.count else { return nil }
        return ShortcutSplitLauncherBindingPreflight(
            catalog: catalog,
            bindingBatch: bindingBatch,
            entries: entries
        )
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        let preparedMoves = preflight.entries.map(\.preparedMove)
        guard preflight.catalog === catalog,
              preparedMoves.allSatisfy({
                  insertion.sourceCatalog.contains($0.pinReceipt)
              }), catalog.matches(insertion.sourceCatalog) else { return nil }
        return prepareContribution(
            preflight,
            terminalMoves: preparedMoves,
            insertion: insertion
        )
    }
}
