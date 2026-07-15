@MainActor
extension ShortcutSplitLauncherMoveBatchStaging {
    func prepareContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        terminalRestorations restorations: [
            PreparedShortcutSplitLauncherRestoration
        ],
        insertion: ShortcutSplitLauncherCatalogInsertionPlan? = nil
    ) -> ShortcutSplitLauncherBindingContribution? {
        guard preflight.catalog === catalog,
              restorations.count == preflight.entries.count,
              preflight.bindingBatch.builder.isCurrent() else { return nil }
        let source = insertion?.sourceCatalog ?? catalog.snapshot()
        guard catalog.matches(source) else { return nil }
        var moves: [ShortcutSplitLauncherPreparedMove] = []
        for (restoration, prepared) in zip(
            restorations,
            preflight.entries.map(\.binding)
        ) {
            guard let pin = catalog.currentPin(withID: restoration.pin.id),
                  let target = catalog.preview(
                      pin,
                      destination: restoration.destination
                  ), prepared.pinTarget.accepts(target),
                  let binding = preflight.bindingBatch.prepareTransaction(
                      pin: target,
                      prepared: prepared
                  ) else {
                cancelPreparedMoves(moves)
                return nil
            }
            moves.append(ShortcutSplitLauncherPreparedMove(
                binding: binding,
                destination: restoration.destination
            ))
        }
        let plan = ShortcutSplitLauncherCatalogMovePlan(
            insertion: insertion?.insertion,
            entries: zip(restorations, moves).map { restoration, move in
                ShortcutSplitLauncherCatalogMovePlan.Entry(
                    pinID: restoration.pin.id,
                    destination: move.destination,
                    target: move.binding.pinTarget
                )
            }
        )
        let checkpoint = ShortcutSplitLauncherMoveBatchCheckpoint(
            catalog: catalog,
            source: source,
            plan: plan
        )
        let folders = ShortcutSplitLauncherFolderPublicationGate(
            folderIDs: Set(moves.compactMap(\.destination.folderId))
        )
        return ShortcutSplitLauncherBindingContribution(
            builder: preflight.bindingBatch.builder,
            binding: ShortcutTabBindingBatchContribution(
                inputs: moves.map(\.binding.input),
                profileAdmissions: moves.flatMap(
                    \.binding.profileAdmissions
                ),
                residences: moves.map {
                    ShortcutTabBindingResidenceReceiptTransaction(
                        $0.binding.input.residences
                    )
                }
            ),
            checkpoint: checkpoint,
            folders: folders
        )
    }

    private func cancelPreparedMoves(
        _ moves: [ShortcutSplitLauncherPreparedMove]
    ) {
        moves.reversed().forEach {
            precondition($0.binding.input.residences.cancelPrepared())
        }
    }
}
