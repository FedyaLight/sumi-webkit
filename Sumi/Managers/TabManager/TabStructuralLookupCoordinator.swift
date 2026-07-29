import Foundation

/// Owns the exact tab lookup index and coalesced structural publication batch.
@MainActor
final class TabStructuralLookupCoordinator {
    private let stateStore: TabStateStore

    /// Shared by membership queries and deterministic session teardown.
    let lookupOwner: TabStructuralLookupOwner
    private let publishOwner: TabStructuralPublishOwner

    init(
        eventBus: TabStructureEventBus,
        stateStore: TabStateStore
    ) {
        self.lookupOwner = TabStructuralLookupOwner()
        self.publishOwner = TabStructuralPublishOwner(eventBus: eventBus)
        self.stateStore = stateStore
    }

    var batchFlushCount: Int { lookupOwner.batchFlushCount }
    var immediateFlushCount: Int { lookupOwner.immediateFlushCount }
    var mutationRevision: UInt64 { publishOwner.mutationRevision }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: stateStore.regularTabs.tabsBySpaceSnapshot(),
            transientShortcutTabsByWindow:
                stateStore.transientTabs.transientShortcutTabsByWindow,
            transientExtensionTabsByID:
                stateStore.transientTabs.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID:
                stateStore.transientTabs.auxiliaryMiniWindowTabsByID
        )
    }

    func rebuild() {
        lookupOwner.rebuild(with: structuralLookupSnapshot)
    }

    @discardableResult
    func withTransaction<T>(
        _ operation: @MainActor @Sendable () throws -> T
    ) rethrows -> T {
        try publishOwner.withTransaction(
            flushPendingLookupBatch: { self.flushPendingBatchIfNeeded() },
            operation
        )
    }

    func requestPublish(scope: TabStructureChangeScope = .all) {
        publishOwner.requestPublish(scope: scope)
    }

    @discardableResult
    func publishFolderExpansionChange(
        spaceID: UUID,
        expansionByFolderID: [UUID: Bool]
    ) -> TabFolderExpansionChange {
        publishOwner.publishFolderExpansionChange(
            spaceID: spaceID,
            expansionByFolderID: expansionByFolderID
        )
    }

    /// Makes writes queued by the current structural transaction available to
    /// an internal reader without opening external structural publication.
    func flushPendingWritesForRead() {
        precondition(
            publishOwner.isBatching,
            "Lookup read checkpoint requires a structural transaction"
        )
        flushPendingBatchIfNeeded()
    }

    func runAfterCurrentBatch(_ action: @escaping @MainActor () -> Void) {
        publishOwner.runAfterCurrentBatch(action)
    }

    func runBeforeCurrentBatchPublication(
        _ action: @escaping @MainActor () -> Void
    ) {
        publishOwner.runBeforeCurrentBatchPublication(action)
    }

    func notifyTransientShortcutStateChanged(
        entries: [LiveShortcutTabEntry]
    ) {
        queueTransientRefresh()
        requestPublish(scope: .runtimeOnly)
        publishOwner.requestLivePageResidencePublish(
            pages: Set(entries.map(\.presentationPage.residenceScope))
        )
    }

    func queueEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        lookupOwner.queueEntries(
            removing: previousTabs,
            with: currentTabs,
            batching: publishOwner.isBatching
        )
    }

    func removeAll() {
        lookupOwner.removeAll()
    }

    private func queueTransientRefresh() {
        lookupOwner.queueTransientRefresh(
            snapshot: structuralLookupSnapshot,
            batching: publishOwner.isBatching
        )
    }

    private func flushPendingBatchIfNeeded() {
        lookupOwner.flushBatchIfNeeded(snapshot: structuralLookupSnapshot)
    }
}
