@MainActor
extension ShortcutSplitLauncherMoveBatchStaging {
    func prepareContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        terminalMoves preparedMoves: [
            PreparedShortcutSplitLauncherMove
        ],
        insertion: ShortcutSplitLauncherCatalogInsertionPlan? = nil
    ) -> ShortcutSplitLauncherBindingContribution? {
        guard preflight.catalog === catalog,
              preparedMoves.count == preflight.entries.count,
              preflight.bindingBatch.builder.isCurrent() else { return nil }
        let source = insertion?.sourceCatalog ?? catalog.snapshot()
        guard catalog.matches(source) else { return nil }
        var moves: [ShortcutSplitLauncherPreparedMove] = []
        for (preparedMove, prepared) in zip(
            preparedMoves,
            preflight.entries.map(\.binding)
        ) {
            guard let pin = catalog.currentPin(withID: preparedMove.pin.id),
                  let target = catalog.preview(
                      pin,
                      destination: preparedMove.destination
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
                destination: preparedMove.destination
            ))
        }
        let plan = ShortcutSplitLauncherCatalogMovePlan(
            insertion: insertion?.insertion,
            entries: zip(preparedMoves, moves).map { preparedMove, move in
                ShortcutSplitLauncherCatalogMovePlan.Entry(
                    pinID: preparedMove.pin.id,
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
