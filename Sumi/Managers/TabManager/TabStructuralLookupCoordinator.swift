import Foundation

/// Owns the exact tab lookup index and coalesced structural publication batch.
@MainActor
final class TabStructuralLookupCoordinator {
    private let tabsBySpace: @MainActor () -> [UUID: [Tab]]
    private let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]
    private let transientExtensionTabsByID: @MainActor () -> [UUID: Tab]
    private let auxiliaryMiniWindowTabsByID: @MainActor () -> [UUID: Tab]

    /// Exposed so `TabManager` can hand the same lookup index to
    /// `TabCollectionMembershipOwner` and tear it down in `deinit`.
    let lookupOwner: TabStructuralLookupOwner
    private let publishOwner: TabStructuralPublishOwner

    init(
        eventBus: TabStructureEventBus,
        tabsBySpace: @escaping @MainActor () -> [UUID: [Tab]],
        transientShortcutTabsByWindow: @escaping @MainActor () -> [UUID: [UUID: Tab]],
        transientExtensionTabsByID: @escaping @MainActor () -> [UUID: Tab],
        auxiliaryMiniWindowTabsByID: @escaping @MainActor () -> [UUID: Tab]
    ) {
        self.lookupOwner = TabStructuralLookupOwner()
        self.publishOwner = TabStructuralPublishOwner(eventBus: eventBus)
        self.tabsBySpace = tabsBySpace
        self.transientShortcutTabsByWindow = transientShortcutTabsByWindow
        self.transientExtensionTabsByID = transientExtensionTabsByID
        self.auxiliaryMiniWindowTabsByID = auxiliaryMiniWindowTabsByID
    }

    var batchFlushCount: Int { lookupOwner.batchFlushCount }
    var immediateFlushCount: Int { lookupOwner.immediateFlushCount }
    var mutationRevision: UInt64 { publishOwner.mutationRevision }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: tabsBySpace(),
            transientShortcutTabsByWindow: transientShortcutTabsByWindow(),
            transientExtensionTabsByID: transientExtensionTabsByID(),
            auxiliaryMiniWindowTabsByID: auxiliaryMiniWindowTabsByID()
        )
    }

    func rebuild() {
        lookupOwner.rebuild(with: structuralLookupSnapshot)
    }

    @discardableResult
    func withTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try publishOwner.withTransaction(
            flushPendingLookupBatch: { self.flushPendingBatchIfNeeded() },
            operation
        )
    }

    func requestPublish(scope: TabStructureChangeScope = .all) {
        publishOwner.requestPublish(scope: scope)
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
        entries.forEach { publishTransientShortcutPageChange($0) }
    }

    private func publishTransientShortcutPageChange(
        _ entry: LiveShortcutTabEntry
    ) {
        requestPublish(scope: entry.pageScope)
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
