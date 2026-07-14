import Foundation
import OSLog

@MainActor
final class TabStructuralPublishOwner {
    private let eventBus: TabStructureEventBus
    private var structuralUpdateDepth = 0
    private var pendingStructuralScope: TabStructureChangeScope?
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

    private func emitStructureChanged(scope: TabStructureChangeScope) {
        eventBus.publishStructureChanged(scope: scope)
    }

    private func begin() {
        if structuralUpdateDepth == 0 {
            mutationRevision += 1
            structuralTransactionSignpostState = PerformanceTrace.beginInterval("TabManager.structuralTransaction")
        }
        structuralUpdateDepth += 1
    }

    private func end(flushPendingLookupBatch: () -> Void) {
        guard structuralUpdateDepth > 0 else { return }
        structuralUpdateDepth -= 1
        guard structuralUpdateDepth == 0 else { return }

        flushPendingLookupBatch()
        let scope = pendingStructuralScope
        pendingStructuralScope = nil
        if let state = structuralTransactionSignpostState {
            PerformanceTrace.endInterval("TabManager.structuralTransaction", state)
            structuralTransactionSignpostState = nil
        }
        if let scope {
            PerformanceTrace.emitEvent("TabManager.structuralPublish.coalesced")
            emitStructureChanged(scope: scope)
        }
        let actions = actionsAfterStructuralBatch
        actionsAfterStructuralBatch.removeAll(keepingCapacity: true)
        actions.forEach { $0() }
    }
}
