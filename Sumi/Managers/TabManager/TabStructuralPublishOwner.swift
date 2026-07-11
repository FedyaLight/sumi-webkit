import Foundation
import OSLog

@MainActor
final class TabStructuralPublishOwner {
    private let eventBus: TabStructureEventBus
    private var structuralUpdateDepth = 0
    private var pendingStructuralPublish = false
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

    func requestPublish() {
        if structuralUpdateDepth > 0 {
            pendingStructuralPublish = true
            return
        }

        mutationRevision += 1
        PerformanceTrace.emitEvent("TabManager.structuralPublish.immediate")
        emitStructureChanged()
    }

    func runAfterCurrentBatch(_ action: @escaping @MainActor () -> Void) {
        guard structuralUpdateDepth > 0 else {
            action()
            return
        }
        actionsAfterStructuralBatch.append(action)
    }

    private func emitStructureChanged() {
        eventBus.publishStructureChanged()
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
        let shouldPublish = pendingStructuralPublish
        pendingStructuralPublish = false
        if let state = structuralTransactionSignpostState {
            PerformanceTrace.endInterval("TabManager.structuralTransaction", state)
            structuralTransactionSignpostState = nil
        }
        if shouldPublish {
            PerformanceTrace.emitEvent("TabManager.structuralPublish.coalesced")
            emitStructureChanged()
        }
        let actions = actionsAfterStructuralBatch
        actionsAfterStructuralBatch.removeAll(keepingCapacity: true)
        actions.forEach { $0() }
    }
}
