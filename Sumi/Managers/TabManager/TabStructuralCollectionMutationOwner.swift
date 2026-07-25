import Foundation

@MainActor
final class TabStructuralCollectionMutationOwner {
    private struct AvailabilityObservation {
        let id: UUID
        let action: @MainActor () -> Void
    }

    private let store: TabStructuralCollectionStore
    private let snapshots: TabStructuralCollectionSnapshotStore
    private let publisher: TabStructuralMutationPublisher
    private var transaction: TabStructuralMutationTransaction?
    private var settlingTransaction: TabStructuralMutationTransaction?
    private var settlingTarget: TabStructuralMutationTransaction.Snapshot?
    private var isApplyingSettlement = false
    private var foreignMutationDepth = 0
    private var availabilityObservation: AvailabilityObservation?

    var isAvailabilityObservationActive: Bool {
        availabilityObservation != nil
    }

    var hasOpenAggregate: Bool {
        transaction != nil
    }

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
        guard transaction == nil,
              settlingTransaction == nil,
              foreignMutationDepth == 0 else { return nil }
        return openAggregate()
    }

    func observeNextAvailability(
        _ action: @escaping @MainActor () -> Void
    ) -> UUID? {
        guard transaction != nil
                || settlingTransaction != nil
                || foreignMutationDepth > 0 else {
            return nil
        }
        precondition(
            availabilityObservation == nil,
            "Structural availability already has an observer"
        )
        let id = UUID()
        availabilityObservation = AvailabilityObservation(
            id: id,
            action: action
        )
        return id
    }

    func cancelAvailabilityObservation(_ id: UUID) {
        guard availabilityObservation?.id == id else { return }
        availabilityObservation = nil
    }

    func schedulePersistence() {
        publisher.schedulePersistence()
    }

    private func openAggregate() -> PreparedAggregate {
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

    func setFolderPlacements(
        _ placements: [UUID: TabFolderPlacement],
        in items: [TabFolder],
        for spaceId: UUID
    ) {
        mutate {
            let previous = store.folders(for: spaceId)
            guard items.contains(where: { folder in
                guard let placement = placements[folder.id] else { return false }
                return folder.placementSnapshot != placement
            }) else { return }
            willMutate()
            precondition(TabStructuralMutationTransaction.applyFolderPlacements(
                placements,
                to: items
            ))
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

    @discardableResult
    func removePinnedTabs(for profileId: UUID) -> [ShortcutPin]? {
        guard store.profilePinsEntry(for: profileId) != nil else { return nil }
        var removed: [ShortcutPin]?
        mutate {
            guard let previous = store.profilePinsEntry(for: profileId) else {
                return
            }
            removed = previous
            willMutate()
            store.removeProfilePins(for: profileId)
            record(.profilePins(
                profileId,
                previous: previous,
                current: [],
                allPins: store.allPins()
            ))
        }
        return removed
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
        _ settlement: TabStructuralMutationTransaction.Settlement,
        from candidate: TabStructuralMutationTransaction
    ) -> Bool {
        guard settlingTransaction === candidate else { return false }
        isApplyingSettlement = true
        switch settlement {
        case .committed:
            publisher.publish(settlement)
        case .rolledBack(let snapshot):
            publisher.publishFolderExpansionChanges(
                snapshots.restore(snapshot)
            )
        }
        isApplyingSettlement = false
        settlingTransaction = nil
        settlingTarget = nil
        publishAvailabilityIfNeeded()
        return true
    }

    func seal(
        _ candidate: TabStructuralMutationTransaction
    ) -> TabStructuralMutationTransaction.Snapshot? {
        guard transaction === candidate,
              settlingTransaction == nil else { return nil }
        let target = snapshots.capture()
        transaction = nil
        settlingTransaction = candidate
        settlingTarget = target
        return target
    }

    func releaseOpen(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        guard transaction === candidate,
              settlingTransaction == nil else { return false }
        transaction = nil
        settlingTransaction = candidate
        settlingTarget = nil
        return true
    }

    func discardReleased(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        guard settlingTransaction === candidate else { return false }
        settlingTransaction = nil
        settlingTarget = nil
        publishAvailabilityIfNeeded()
        return true
    }

    func abandonSettlement(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        discardReleased(candidate)
    }

    func compensateInvalidatedSettlement(
        _ candidate: TabStructuralMutationTransaction,
        source: TabStructuralMutationTransaction.Snapshot
    ) -> Bool {
        guard settlingTransaction === candidate,
              let settlingTarget else { return false }
        publisher.publishFolderExpansionChanges(
            snapshots.restoreUncontended(
                source: source,
                target: settlingTarget
            )
        )
        settlingTransaction = nil
        self.settlingTarget = nil
        publishAvailabilityIfNeeded()
        return true
    }

    func ownsOpen(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        transaction === candidate
    }

    func ownsSettlement(
        _ candidate: TabStructuralMutationTransaction
    ) -> Bool {
        settlingTransaction === candidate
    }

    func currentSnapshotMatches(
        _ expected: TabStructuralMutationTransaction.Snapshot
    ) -> Bool {
        snapshots.matches(expected)
    }

    private func willMutate() {
        if transaction == nil { publisher.announceStateChange() }
    }

    private func mutate(_ operation: @MainActor @Sendable () -> Void) {
        if transaction != nil {
            operation()
            return
        }
        beginForeignMutation()
        publisher.withTransaction {
            operation()
        }
        endForeignMutation()
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

    private func publishAvailabilityIfNeeded() {
        guard transaction == nil,
              settlingTransaction == nil,
              foreignMutationDepth == 0,
              let observation = availabilityObservation else { return }
        availabilityObservation = nil
        observation.action()
    }

    private func beginForeignMutation() {
        let beginsOuterMutation = foreignMutationDepth == 0
        foreignMutationDepth += 1
        if beginsOuterMutation,
           isApplyingSettlement == false,
           let settlingTransaction,
           let settlingTarget {
            let source = settlingTransaction.discardInvalidated()
            publisher.publishFolderExpansionChanges(
                snapshots.restoreUncontended(
                    source: source,
                    target: settlingTarget
                )
            )
            self.settlingTransaction = nil
            self.settlingTarget = nil
        }
    }

    private func endForeignMutation() {
        precondition(foreignMutationDepth > 0)
        foreignMutationDepth -= 1
        publishAvailabilityIfNeeded()
    }

    private static func sortedTabs(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
