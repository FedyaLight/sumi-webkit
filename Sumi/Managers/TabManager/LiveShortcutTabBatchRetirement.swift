import Foundation

/// Atomically retires a complete set of physical shortcut residences and
/// publishes the union of their retained presentation pages once.
@MainActor
final class LiveShortcutTabBatchRetirement {
    private let storage: TabTransientTabRegistryOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        storage: TabTransientTabRegistryOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.storage = storage
        self.structuralLookup = structuralLookup
    }

    func remove(pinIDs: Set<UUID>) -> [LiveShortcutTabEntry] {
        remove { pinIDs.contains($0.pinId) }
    }

    func remove(
        pinIDs: Set<UUID>,
        in windowID: UUID
    ) -> [LiveShortcutTabEntry] {
        remove { $0.windowId == windowID && pinIDs.contains($0.pinId) }
    }

    func remove(presentedInSpace spaceID: UUID) -> [LiveShortcutTabEntry] {
        remove { $0.presentationPage.page.spaceID == spaceID }
    }

    func removeAll() -> [LiveShortcutTabEntry] {
        remove { _ in true }
    }

    private func remove(
        matching predicate: (LiveShortcutTabEntry) -> Bool
    ) -> [LiveShortcutTabEntry] {
        guard storage.liveShortcutResidences.contains(matching: predicate) else {
            return []
        }
        return structuralLookup.withTransaction {
            let entries = storage.liveShortcutResidences.removeAll(
                matching: predicate
            )
            precondition(entries.isEmpty == false)
            structuralLookup.notifyTransientShortcutStateChanged(entries: entries)
            return entries
        }
    }
}
