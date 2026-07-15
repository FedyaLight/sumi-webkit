import Foundation

@MainActor
final class TabStructuralCollectionMutationOwner {
    private let store: TabStructuralCollectionStore
    private let snapshots: TabStructuralCollectionSnapshotStore
    private let publisher: TabStructuralMutationPublisher
    private var transaction: TabStructuralMutationTransaction?

    init(
        store: TabStructuralCollectionStore,
        snapshots: TabStructuralCollectionSnapshotStore,
        publisher: TabStructuralMutationPublisher
    ) {
        self.store = store
        self.snapshots = snapshots
        self.publisher = publisher
    }

    func prepareAggregate() -> PreparedAggregate? {
        guard transaction == nil else { return nil }
        let transaction = TabStructuralMutationTransaction(
            snapshot: snapshots.capture()
        )
        self.transaction = transaction
        return PreparedAggregate(owner: self, transaction: transaction)
    }

    func withReversibleSideEffects(_ operation: () -> Bool) -> Bool {
        guard let aggregate = prepareAggregate() else {
            preconditionFailure("Nested structural mutation transaction")
        }
        let committed = operation()
        if committed {
            guard aggregate.stage(), aggregate.publish() else {
                preconditionFailure("Structural mutation settlement diverged")
            }
        } else {
            precondition(
                aggregate.rollback(),
                "Structural mutation rollback diverged"
            )
        }
        return committed
    }

    func setTabs(_ items: [Tab], for spaceId: UUID) {
        mutate {
            let previous = store.tabs(for: spaceId)
            let current = Self.sortedTabs(items)
            willMutate()
            store.replaceTabs(current, for: spaceId)
            tabsDidChange()
            record(.regularTabs(
                spaceId,
                previous: previous,
                current: current
            ))
        }
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        mutate {
            let previous = store.folders(for: spaceId)
            willMutate()
            store.replaceFolders(items, for: spaceId)
            record(.folders(
                spaceId,
                previous: previous,
                current: items
            ))
        }
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        mutate {
            let previous = store.profilePins(for: profileId)
            willMutate()
            store.replaceProfilePins(items, for: profileId)
            record(.profilePins(
                profileId,
                previous: previous,
                current: items,
                allPins: store.allPins()
            ))
        }
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        mutate {
            let previous = store.spacePins(for: spaceId)
            willMutate()
            store.replaceSpacePins(items, for: spaceId)
            record(.spacePins(
                spaceId,
                previous: previous,
                current: items,
                allPins: store.allPins()
            ))
        }
    }

    func apply(
        _ settlement: TabStructuralMutationTransaction.Settlement
    ) {
        switch settlement {
        case .committed:
            publisher.publish(settlement)
        case .rolledBack(let snapshot):
            snapshots.restore(snapshot)
        }
    }

    func seal(
        _ candidate: TabStructuralMutationTransaction
    ) -> TabStructuralMutationTransaction.Snapshot? {
        guard transaction === candidate else { return nil }
        let target = snapshots.capture()
        transaction = nil
        return target
    }

    func releaseOpen(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        guard transaction === candidate else { return false }
        transaction = nil
        return true
    }

    func ownsOpen(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        transaction === candidate
    }

    func currentSnapshotMatches(
        _ expected: TabStructuralMutationTransaction.Snapshot
    ) -> Bool {
        snapshots.matches(expected)
    }

    private func willMutate() {
        if transaction == nil { publisher.announceStateChange() }
    }

    private func mutate(_ operation: () -> Void) {
        if transaction == nil {
            publisher.withTransaction(operation)
        } else {
            operation()
        }
    }

    private func tabsDidChange() {
        if let transaction {
            transaction.recordTabsReplacement()
        } else {
            publisher.publishTabsSnapshot()
        }
    }

    private func record(_ effect: TabStructuralMutationTransaction.Effect) {
        if let transaction {
            transaction.record(effect)
        } else {
            publisher.publish(effect)
        }
    }

    private static func sortedTabs(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
