import Foundation

/// Exact terminal retirement for the internal regular tab used as an empty
/// split placeholder. It removes canonical collection and lookup residence
/// without observation; the enclosing split transaction owns window
/// settlement, while runtime teardown and persistence publish afterward.
@MainActor
final class EmptySplitPlaceholderRetirementReceipt {
    private enum State {
        case prepared
        case committed(RegularTabCollectionOwner.Removal)
        case published
        case cancelled
    }

    private let placeholder: Tab
    private let spaceID: UUID
    private let regularTabs: RegularTabCollectionOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private let runtimeCleanup: RegularTabClosureRuntimeCleanup
    private var state = State.prepared

    init?(
        placeholder: Tab,
        regularTabs: RegularTabCollectionOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService,
        runtimeConnection: TabRuntimePortConnection,
        runtimeCleanup: RegularTabClosureRuntimeCleanup
    ) {
        let runtimeLease = runtimeConnection.captureLease()
        guard let spaceID = placeholder.spaceId,
              regularTabs.containsIdentical(
                  placeholder,
                  in: spaceID
              ), runtimeLease.registry != nil else { return nil }
        self.placeholder = placeholder
        self.spaceID = spaceID
        self.regularTabs = regularTabs
        self.structuralLookup = structuralLookup
        self.persistence = persistence
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        self.runtimeCleanup = runtimeCleanup
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return regularTabs.containsIdentical(placeholder, in: spaceID)
            && runtimeConnection.accepts(runtimeLease)
    }

    @discardableResult
    func commitModel() -> Bool {
        guard isCurrent(), let removal = regularTabs.remove(
            ifIdentical: placeholder,
            from: spaceID,
            currentSpaceId: nil
        ) else { return false }
        state = .committed(removal)
        structuralLookup.queueEntries(
            removing: [placeholder],
            with: []
        )
        // Cancel the retired object's queued runtime write while the exact
        // removal is still observation-silent. A same-UUID replacement may
        // become canonical once terminal publication starts and must not have
        // its persistence cancelled by this stale receipt.
        persistence.cancelRuntimeStatePersistence(for: placeholder.id)
        return true
    }

    func publish() {
        guard case .committed(let removal) = state,
              let runtime = runtimeLease.registry else { return }
        state = .published
        runtimeCleanup.releaseConfirmedRemovals([removal], runtime: runtime)
        persistence.scheduleStructuralPersistence()
        _ = runtime.validateWindowStates()
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
    }
}
