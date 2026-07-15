import Foundation

/// Raw, rollback-capable residence mutations. No structure event is emitted
/// until `publish`, so an aggregate consumer can reject without observable
/// intermediate registry state.
@MainActor
final class LiveShortcutResidenceMutationStaging {
    enum Change {
        case registration(LiveShortcutTabEntry)
        case removal(LiveShortcutTabEntry)
        case relocation(
            previous: LiveShortcutTabEntry,
            current: LiveShortcutTabEntry
        )

        var affectedEntries: [LiveShortcutTabEntry] {
            switch self {
            case .registration(let entry), .removal(let entry):
                return [entry]
            case .relocation(let previous, let current):
                return [previous, current]
            }
        }

        var currentEntry: LiveShortcutTabEntry? {
            switch self {
            case .registration(let entry):
                return entry
            case .removal:
                return nil
            case .relocation(_, let current):
                return current
            }
        }
    }

    private let storage: LiveShortcutTabResidenceStore
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        storage: LiveShortcutTabResidenceStore,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.storage = storage
        self.structuralLookup = structuralLookup
    }

    func canRelocate(
        _ tab: Tab,
        from sourcePinID: UUID,
        to targetPinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Bool {
        storage.canRelocate(
            tab,
            from: sourcePinID,
            to: targetPinID,
            in: windowID,
            presentationPage: presentationPage
        )
    }

    func register(
        _ tab: Tab,
        for pinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Change? {
        storage.register(
            tab,
            for: pinID,
            in: windowID,
            presentationPage: presentationPage
        ).map(Change.registration)
    }

    func relocate(
        _ tab: Tab,
        from sourcePinID: UUID,
        to targetPinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Change? {
        storage.relocate(
            tab,
            from: sourcePinID,
            to: targetPinID,
            in: windowID,
            presentationPage: presentationPage
        ).map {
            .relocation(previous: $0.previous, current: $0.current)
        }
    }

    func remove(_ expected: LiveShortcutTabEntry) -> Change? {
        storage.remove(ifMatching: expected) ? .removal(expected) : nil
    }

    func canPublish(_ changes: [Change]) -> Bool {
        changes.allSatisfy { change in
            switch change {
            case .removal(let entry):
                return storage.snapshot.entry(containing: entry.tab) == nil
                    && storage.snapshot.entries(in: entry.windowId)
                        .contains { $0.pinId == entry.pinId } == false
            case .registration, .relocation:
                guard let expected = change.currentEntry,
                      let current = storage.snapshot.entry(
                          containing: expected.tab
                      ) else { return false }
                return current.isIdentical(to: expected)
            }
        }
    }

    @discardableResult
    func rollback(_ changes: [Change]) -> Bool {
        guard canPublish(changes) else { return false }
        for change in changes.reversed() {
            switch change {
            case .registration(let entry):
                guard storage.remove(ifMatching: entry) else { return false }
            case .removal(let entry):
                guard storage.register(
                    entry.tab,
                    for: entry.pinId,
                    in: entry.windowId,
                    presentationPage: entry.presentationPage
                )?.isIdentical(to: entry) == true else { return false }
            case .relocation(let previous, let current):
                guard storage.relocate(
                    current.tab,
                    from: current.pinId,
                    to: previous.pinId,
                    in: current.windowId,
                    presentationPage: previous.presentationPage
                )?.previous.isIdentical(to: current) == true else {
                    return false
                }
            }
        }
        return true
    }

    func publish(_ changes: [Change]) {
        structuralLookup.notifyTransientShortcutStateChanged(
            entries: changes.flatMap(\.affectedEntries)
        )
    }

    func beginBatchCheckpoint() -> LiveShortcutResidenceBatchCheckpoint {
        LiveShortcutResidenceBatchCheckpoint(storage: storage)
    }
}

/// Exact raw residence checkpoint reserved for a transaction that has emitted
/// no observation yet. Once sealed, compensation is admitted only while the
/// complete staged snapshot is still current.
@MainActor
final class LiveShortcutResidenceBatchCheckpoint {
    private enum State {
        case open
        case sealed(LiveShortcutTabSnapshot)
        case restored
    }

    private let storage: LiveShortcutTabResidenceStore
    private let source: LiveShortcutTabSnapshot
    private var state: State = .open

    fileprivate init(storage: LiveShortcutTabResidenceStore) {
        self.storage = storage
        source = storage.snapshot
    }

    func seal() {
        guard case .open = state else {
            preconditionFailure("Residence batch checkpoint was already sealed")
        }
        state = .sealed(storage.snapshot)
    }

    func isCurrent() -> Bool {
        guard case .sealed(let expected) = state else { return false }
        return storage.snapshot.isIdentical(to: expected)
    }

    func restore() -> Bool {
        switch state {
        case .open:
            break
        case .sealed where isCurrent():
            break
        case .sealed, .restored:
            return false
        }
        storage.restore(source)
        state = .restored
        return storage.snapshot.isIdentical(to: source)
    }
}
