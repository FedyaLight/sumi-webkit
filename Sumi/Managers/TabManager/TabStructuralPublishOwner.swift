import Foundation

@MainActor
final class TabStructuralPublishOwner {
    private let eventBus: TabStructureEventBus
    private var structuralUpdateDepth = 0
    private var pendingStructuralScope: TabStructureChangeScope?
    private var pendingLivePageResidenceScopes = Set<LivePageResidenceScope>()
    private var actionsBeforeStructuralPublication: [@MainActor () -> Void] = []
    private var actionsAfterStructuralBatch: [@MainActor () -> Void] = []
    private var structuralTransactionSignpostState:
        PerformanceTrace.IntervalState?
    private(set) var mutationRevision: UInt64 = 0

    init(eventBus: TabStructureEventBus) {
        self.eventBus = eventBus
    }

    var isBatching: Bool {
        structuralUpdateDepth > 0
    }

    @discardableResult
    func withTransaction<T>(
        flushPendingLookupBatch: @MainActor @Sendable () -> Void,
        _ operation: @MainActor @Sendable () throws -> T
    ) rethrows -> T {
        begin()
        defer {
            end(flushPendingLookupBatch: flushPendingLookupBatch)
        }
        return try operation()
    }

    func requestPublish(scope: TabStructureChangeScope = .all) {
        if structuralUpdateDepth > 0 {
            if pendingStructuralScope == nil {
                mutationRevision += 1
            }
            pendingStructuralScope = pendingStructuralScope?.merging(scope) ?? scope
            return
        }

        mutationRevision += 1
        PerformanceTrace.emitEvent("TabManager.structuralPublish.immediate")
        emitStructureChanged(scope: scope)
    }

    func requestLivePageResidencePublish(
        pages: Set<LivePageResidenceScope>
    ) {
        guard !pages.isEmpty else { return }
        if structuralUpdateDepth > 0 {
            pendingLivePageResidenceScopes.formUnion(pages)
            return
        }
        emitLivePageResidenceChanged(pages)
    }

    @discardableResult
    func publishFolderExpansionChange(
        spaceID: UUID,
        expansionByFolderID: [UUID: Bool]
    ) -> TabFolderExpansionChange {
        precondition(expansionByFolderID.isEmpty == false)
        mutationRevision += 1
        let change = TabFolderExpansionChange(
            revision: mutationRevision,
            spaceID: spaceID,
            expansionByFolderID: expansionByFolderID
        )
        eventBus.publishFolderExpansionChanged(change)
        return change
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

    private func emitLivePageResidenceChanged(
        _ pages: Set<LivePageResidenceScope>
    ) {
        let sortedPages = pages.sorted {
            if $0.windowID != $1.windowID {
                return $0.windowID.uuidString < $1.windowID.uuidString
            }
            if $0.spaceID != $1.spaceID {
                return $0.spaceID.uuidString < $1.spaceID.uuidString
            }
            return false
        }
        for page in sortedPages {
            eventBus.publishLivePageResidenceChanged(page)
        }
    }

    private func begin() {
        if structuralUpdateDepth == 0 {
            structuralTransactionSignpostState = PerformanceTrace.beginInterval("TabManager.structuralTransaction")
        }
        structuralUpdateDepth += 1
    }

    private func end(
        flushPendingLookupBatch: @MainActor @Sendable () -> Void
    ) {
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
        let livePageResidenceScopes = pendingLivePageResidenceScopes
        pendingLivePageResidenceScopes.removeAll(keepingCapacity: true)
        if let state = structuralTransactionSignpostState {
            PerformanceTrace.endInterval("TabManager.structuralTransaction", state)
            structuralTransactionSignpostState = nil
        }
        if let scope {
            PerformanceTrace.emitEvent("TabManager.structuralPublish.coalesced")
            emitStructureChanged(scope: scope)
        }
        emitLivePageResidenceChanged(livePageResidenceScopes)
        let actions = actionsAfterStructuralBatch
        actionsAfterStructuralBatch.removeAll(keepingCapacity: true)
        actions.forEach { $0() }
    }
}
