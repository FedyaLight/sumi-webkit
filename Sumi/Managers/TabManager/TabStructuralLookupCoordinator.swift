import Combine
import Foundation
import SumiBrowserCore

/// Coordinates the structural-lookup index and structural-publish batching that used to
/// live directly on `TabManager`. It owns the `TabStructuralLookupOwner` (the id→tab index)
/// and the `TabStructuralPublishOwner` (transaction depth + coalesced `structuralChanges`
/// emission), and rebuilds the lookup snapshot from the live tab collections supplied via
/// the initializer closures. `TabManager` keeps thin facades (`withStructuralUpdateTransaction`,
/// `requestStructuralPublish`, `rebuildTabLookup`, `notifyTransientShortcutStateChanged`,
/// `queueTabLookupEntries`) that delegate here so existing callers are unchanged.
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
        structuralChanges: PassthroughSubject<Void, Never>,
        eventBus: TabStructureEventBus? = nil,
        tabsBySpace: @escaping @MainActor () -> [UUID: [Tab]],
        transientShortcutTabsByWindow: @escaping @MainActor () -> [UUID: [UUID: Tab]],
        transientExtensionTabsByID: @escaping @MainActor () -> [UUID: Tab],
        auxiliaryMiniWindowTabsByID: @escaping @MainActor () -> [UUID: Tab]
    ) {
        self.lookupOwner = TabStructuralLookupOwner()
        self.publishOwner = TabStructuralPublishOwner(
            structuralChanges: structuralChanges,
            eventBus: eventBus
        )
        self.tabsBySpace = tabsBySpace
        self.transientShortcutTabsByWindow = transientShortcutTabsByWindow
        self.transientExtensionTabsByID = transientExtensionTabsByID
        self.auxiliaryMiniWindowTabsByID = auxiliaryMiniWindowTabsByID
    }

    var batchFlushCount: Int { lookupOwner.batchFlushCount }
    var immediateFlushCount: Int { lookupOwner.immediateFlushCount }

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

    func requestPublish() {
        publishOwner.requestPublish()
    }

    func notifyTransientShortcutStateChanged() {
        queueTransientRefresh()
        requestPublish()
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
