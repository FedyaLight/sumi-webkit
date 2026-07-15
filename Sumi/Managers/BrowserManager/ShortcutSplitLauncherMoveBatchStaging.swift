import Foundation

/// Stages every launcher move against one catalog and residence snapshot.
/// Failed preparation restores those complete raw snapshots, avoiding stale
/// per-move compensation after sibling moves reindex shared containers.
@MainActor
final class ShortcutSplitLauncherMoveBatchStaging:
    ShortcutSplitLauncherMoveBatchPreparing {
    private let catalog: ShortcutSplitLauncherCatalogTransaction
    private let bindingStaging: ShortcutSplitLauncherBindingStaging
    private let residenceMutations: LiveShortcutResidenceMutationStaging
    private let folderOpenState: TabFolderOpenStateService

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        bindingStaging: ShortcutSplitLauncherBindingStaging,
        residenceMutations: LiveShortcutResidenceMutationStaging,
        folderOpenState: TabFolderOpenStateService
    ) {
        self.catalog = catalog
        self.bindingStaging = bindingStaging
        self.residenceMutations = residenceMutations
        self.folderOpenState = folderOpenState
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
        prepare(restorations, ownsResidenceSnapshot: true)
    }

    func prepareForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        prepare(restorations, ownsResidenceSnapshot: false)
    }

    private func prepare(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        ownsResidenceSnapshot: Bool
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        guard Set(restorations.map { $0.pin.id }).count == restorations.count,
              restorations.allSatisfy({ restoration in
                  catalog.isCurrent(restoration.pin)
                      && accepts(
                          restoration.pin,
                          destination: restoration.destination
                      )
              }) else { return nil }

        let checkpoint = ShortcutSplitLauncherMoveBatchCheckpoint(
            catalog: catalog,
            sourceCatalog: catalog.snapshot(),
            residences: ownsResidenceSnapshot
                ? residenceMutations.beginBatchCheckpoint()
                : nil
        )
        var moves: [ShortcutSplitLauncherStagedMove] = []
        for restoration in restorations {
            guard let pin = checkpoint.currentPin(withID: restoration.pin.id),
                  let move = stage(
                      pin,
                      destination: restoration.destination,
                      checkpoint: checkpoint
                  )
            else {
                if checkpoint.ownsResidenceSnapshot {
                    precondition(checkpoint.restore(),
                                 "Launcher batch compensation was not exact")
                    moves.forEach {
                        $0.bindings.discardAfterAggregateRollback()
                    }
                } else {
                    for move in moves.reversed() {
                        precondition(move.bindings.rollback())
                    }
                    precondition(checkpoint.restoreCatalog())
                }
                return nil
            }
            moves.append(move)
        }

        checkpoint.seal()
        return ShortcutSplitLauncherMoveBatchReceipt(
            checkpoint: checkpoint,
            moves: moves,
            folderOpenState: folderOpenState
        )
    }

    private func stage(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination,
        checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint
    ) -> ShortcutSplitLauncherStagedMove? {
        guard let preview = checkpoint.preview(pin, destination: destination),
              let admission = bindingStaging.admission(for: preview) else {
            return nil
        }
        var bindings: ShortcutTabBindingRefreshTransaction?
        guard checkpoint.move(
            pin,
            destination: destination,
            applying: {
                bindings = self.bindingStaging.stage(
                    pin: $0,
                    admission: admission
                )
                return bindings != nil
            }
        ) != nil, let bindings else { return nil }
        return ShortcutSplitLauncherStagedMove(
            bindings: bindings,
            destination: destination
        )
    }
}
