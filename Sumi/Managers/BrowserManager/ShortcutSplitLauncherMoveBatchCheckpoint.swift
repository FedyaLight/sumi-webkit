import Foundation

/// Owns the exact catalog and residence snapshots for one unpublished move
/// batch. Both halves are sealed and restored as one atomic checkpoint.
@MainActor
final class ShortcutSplitLauncherMoveBatchCheckpoint {
    private let catalog: ShortcutSplitLauncherCatalogTransaction
    private let sourceCatalog: ShortcutSplitLauncherCatalogSnapshot
    private let residences: LiveShortcutResidenceBatchCheckpoint?
    private var finalCatalog: ShortcutSplitLauncherCatalogSnapshot?

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        sourceCatalog: ShortcutSplitLauncherCatalogSnapshot,
        residences: LiveShortcutResidenceBatchCheckpoint?
    ) {
        self.catalog = catalog
        self.sourceCatalog = sourceCatalog
        self.residences = residences
    }

    func currentPin(withID id: UUID) -> ShortcutPin? {
        guard finalCatalog == nil else { return nil }
        return catalog.currentPin(withID: id)
    }

    func preview(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> ShortcutPin? {
        guard finalCatalog == nil else { return nil }
        return catalog.preview(pin, destination: destination)
    }

    func move(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination,
        applying: @escaping (ShortcutPin) -> Bool
    ) -> ShortcutPin? {
        guard finalCatalog == nil else { return nil }
        return catalog.move(pin, destination: destination, applying: applying)
    }

    func seal() {
        precondition(finalCatalog == nil)
        finalCatalog = catalog.snapshot()
        residences?.seal()
    }

    func isCurrent() -> Bool {
        guard let finalCatalog else { return false }
        return catalog.matches(finalCatalog)
            && (residences?.isCurrent() ?? true)
    }

    func restore() -> Bool {
        guard residences?.restore() ?? true else { return false }
        return restoreCatalog()
    }

    func restoreCatalog() -> Bool {
        catalog.restore(sourceCatalog)
        return catalog.matches(sourceCatalog)
    }

    var ownsResidenceSnapshot: Bool { residences != nil }
}
