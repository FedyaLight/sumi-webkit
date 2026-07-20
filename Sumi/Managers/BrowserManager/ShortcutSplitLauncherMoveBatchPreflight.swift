import Foundation

@MainActor
extension ShortcutSplitLauncherMoveBatchStaging {
    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        preflightBindingContribution(
            preparedMoves,
            bindingMode: .preservingLiveBindings
        )
    }

    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> ShortcutSplitLauncherBindingPreflight? {
        guard Set(preparedMoves.map { $0.pin.id }).count == preparedMoves.count,
              preparedMoves.allSatisfy({ catalog.isCurrent($0.pin) }) else {
            return nil
        }
        let bindingBatch = bindingStaging.beginBatch()
        let exclusion: ShortcutLiveRetirementBindingExclusion?
        switch bindingMode {
        case .preservingLiveBindings: exclusion = nil
        case .consumingExactRetirement(let value): exclusion = value
        }
        var didConsumeExclusion = exclusion == nil
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
            let admission: LiveShortcutPresentationRefreshAdmission
            if let exclusion, exclusion.belongs(to: preview) {
                guard didConsumeExclusion == false,
                      let filtered = admitted.consuming(
                          exclusion,
                          for: preview
                      ) else {
                    return nil as ShortcutSplitLauncherBindingPreflight.Entry?
                }
                admission = filtered
                didConsumeExclusion = true
            } else {
                admission = admitted
            }
            guard let binding = bindingBatch.prepare(
                   pin: preview,
                   admission: admission
               ) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            return ShortcutSplitLauncherBindingPreflight.Entry(
                preparedMove: preparedMove,
                binding: binding
            )
        }
        guard entries.count == preparedMoves.count,
              didConsumeExclusion else { return nil }
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
