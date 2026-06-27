import Combine
import Foundation
import OSLog

@MainActor
final class TabStructuralPublishOwner {
    private let structuralChanges: PassthroughSubject<Void, Never>
    private var structuralUpdateDepth = 0
    private var pendingStructuralPublish = false
    private var structuralTransactionSignpostState: OSSignpostIntervalState?

    init(structuralChanges: PassthroughSubject<Void, Never>) {
        self.structuralChanges = structuralChanges
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

        PerformanceTrace.emitEvent("TabManager.structuralPublish.immediate")
        structuralChanges.send()
    }

    private func begin() {
        if structuralUpdateDepth == 0 {
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
            structuralChanges.send()
        }
    }
}
