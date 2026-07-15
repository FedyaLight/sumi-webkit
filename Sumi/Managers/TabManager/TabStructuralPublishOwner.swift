import Foundation
import OSLog

@MainActor
final class TabStructuralPublishOwner {
    private let eventBus: TabStructureEventBus
    private var structuralUpdateDepth = 0
    private var pendingStructuralScope: TabStructureChangeScope?
    private var actionsBeforeStructuralPublication: [@MainActor () -> Void] = []
    private var actionsAfterStructuralBatch: [@MainActor () -> Void] = []
    private var structuralTransactionSignpostState: OSSignpostIntervalState?
    private(set) var mutationRevision: UInt64 = 0

    init(eventBus: TabStructureEventBus) {
        self.eventBus = eventBus
    }

    var isBatching: Bool {
        structuralUpdateDepth > 0
    }

    @discardableResult
    func withTransaction<T>(
        flushPendingLookupBatch: () -> Void,
        _ operation: () throws -> T
    ) rethrows -> T {
        begin()
        defer {
            end(flushPendingLookupBatch: flushPendingLookupBatch)
        }
        return try operation()
    }

    func requestPublish(scope: TabStructureChangeScope = .all) {
        if structuralUpdateDepth > 0 {
            pendingStructuralScope = pendingStructuralScope?.merging(scope) ?? scope
            return
        }

        mutationRevision += 1
        PerformanceTrace.emitEvent("TabManager.structuralPublish.immediate")
        emitStructureChanged(scope: scope)
    }

    func runAfterCurrentBatch(_ action: @escaping @MainActor () -> Void) {
        guard structuralUpdateDepth > 0 else {
            action()
            return
        }
        actionsAfterStructuralBatch.append(action)
    }

    /// Runs terminal ownership work after the raw structural batch and lookup
    /// flush, but before any external structural event. Actions remain inside
    /// the batching sentinel so reentrant structural requests are coalesced
    /// into the same publication instead of escaping as an immediate event.
    func runBeforeCurrentBatchPublication(
        _ action: @escaping @MainActor () -> Void
    ) {
        guard structuralUpdateDepth > 0 else {
            action()
            return
        }
        actionsBeforeStructuralPublication.append(action)
    }

    private func emitStructureChanged(scope: TabStructureChangeScope) {
        eventBus.publishStructureChanged(scope: scope)
    }

    private func begin() {
        if structuralUpdateDepth == 0 {
            structuralTransactionSignpostState = PerformanceTrace.beginInterval("TabManager.structuralTransaction")
        }
        structuralUpdateDepth += 1
    }

    private func end(flushPendingLookupBatch: () -> Void) {
        guard structuralUpdateDepth > 0 else { return }
        guard structuralUpdateDepth == 1 else {
            structuralUpdateDepth -= 1
            return
        }

        flushPendingLookupBatch()
        while actionsBeforeStructuralPublication.isEmpty == false {
            let actions = actionsBeforeStructuralPublication
            actionsBeforeStructuralPublication.removeAll(keepingCapacity: true)
            actions.forEach { $0() }
            flushPendingLookupBatch()
        }
        structuralUpdateDepth = 0
        let scope = pendingStructuralScope
        pendingStructuralScope = nil
        if let state = structuralTransactionSignpostState {
            PerformanceTrace.endInterval("TabManager.structuralTransaction", state)
            structuralTransactionSignpostState = nil
        }
        if let scope {
            mutationRevision += 1
            PerformanceTrace.emitEvent("TabManager.structuralPublish.coalesced")
            emitStructureChanged(scope: scope)
        }
        let actions = actionsAfterStructuralBatch
        actionsAfterStructuralBatch.removeAll(keepingCapacity: true)
        actions.forEach { $0() }
    }
}
