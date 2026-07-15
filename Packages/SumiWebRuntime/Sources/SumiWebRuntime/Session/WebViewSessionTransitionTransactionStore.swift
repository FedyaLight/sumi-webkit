import Foundation

/// Identity-only record of installed replacement and retirement transactions.
/// Previous
/// generations are strongly owned only by `WebViewOwnershipTransitionLedger`;
/// active generations are strongly owned only by the placement store.
@MainActor
final class WebViewSessionTransitionTransactionStore {
    enum SettlementPhase: Equatable {
        case open
        case rollingBack
    }

    enum BatchLease: Equatable {
        case replacement(WebViewReplacementBatchLease)
        case retirement(WebViewRetirementBatchLease)

        var id: UUID {
            switch self {
            case .replacement(let lease):
                return lease.id
            case .retirement(let lease):
                return lease.id
            }
        }
    }

    struct Entry {
        let retirementLease: WebViewRetirementLease
        let installed: WebViewPlacementFingerprint
    }

    struct Batch {
        let lease: BatchLease
        let entriesByTabID: [UUID: Entry]
        let modelTransactionID: UUID?
        var settlementPhase: SettlementPhase = .open
    }

    private var batchesByID: [UUID: Batch] = [:]
    private var batchIDByTabID: [UUID: UUID] = [:]

    var batchIDs: Set<UUID> { Set(batchesByID.keys) }
    var batches: [UUID: Batch] { batchesByID }

    func containsTransaction(for tabID: UUID) -> Bool {
        batchIDByTabID[tabID] != nil
    }

    func batchID(for tabID: UUID) -> UUID? {
        batchIDByTabID[tabID]
    }

    func batch(for lease: WebViewReplacementBatchLease) -> Batch? {
        guard let batch = batchesByID[lease.id],
              batch.lease == .replacement(lease),
              batch.settlementPhase == .open else {
            return nil
        }
        return batch
    }

    func batch(for lease: WebViewRetirementBatchLease) -> Batch? {
        guard let batch = batchesByID[lease.id],
              batch.lease == .retirement(lease),
              batch.settlementPhase == .open else {
            return nil
        }
        return batch
    }

    func claimRetirementRollback(
        for lease: WebViewRetirementBatchLease
    ) -> Batch? {
        guard var batch = batch(for: lease) else { return nil }
        batch.settlementPhase = .rollingBack
        batchesByID[lease.id] = batch
        return batch
    }

    func claimReplacementRollback(
        for lease: WebViewReplacementBatchLease
    ) -> Batch? {
        guard var batch = batch(for: lease) else { return nil }
        batch.settlementPhase = .rollingBack
        batchesByID[lease.id] = batch
        return batch
    }

    func rollingBackBatch(
        for lease: WebViewReplacementBatchLease
    ) -> Batch? {
        guard let batch = batchesByID[lease.id],
              batch.lease == .replacement(lease),
              batch.settlementPhase == .rollingBack else {
            return nil
        }
        return batch
    }

    func rollingBackBatch(
        for lease: WebViewRetirementBatchLease
    ) -> Batch? {
        guard let batch = batchesByID[lease.id],
              batch.lease == .retirement(lease),
              batch.settlementPhase == .rollingBack else {
            return nil
        }
        return batch
    }

    func releaseRetirementRollbackClaim(
        for lease: WebViewRetirementBatchLease
    ) -> Batch? {
        guard var batch = rollingBackBatch(for: lease) else { return nil }
        batch.settlementPhase = .open
        batchesByID[lease.id] = batch
        return batch
    }

    func install(_ batch: Batch) {
        precondition(batchesByID[batch.lease.id] == nil)
        for tabID in batch.entriesByTabID.keys {
            precondition(batchIDByTabID[tabID] == nil)
        }
        batchesByID[batch.lease.id] = batch
        for tabID in batch.entriesByTabID.keys {
            batchIDByTabID[tabID] = batch.lease.id
        }
    }

    func finish(_ batch: Batch) {
        if batchesByID[batch.lease.id]?.lease == batch.lease {
            batchesByID.removeValue(forKey: batch.lease.id)
        }
        for tabID in batch.entriesByTabID.keys
            where batchIDByTabID[tabID] == batch.lease.id {
            batchIDByTabID.removeValue(forKey: tabID)
        }
    }

    func removeAll() {
        batchesByID.removeAll()
        batchIDByTabID.removeAll()
    }

    func assertConsistency(_ context: StaticString) {
        #if DEBUG
            for (tabID, batchID) in batchIDByTabID {
                assert(
                    batchesByID[batchID]?.entriesByTabID[tabID] != nil,
                    "Transition tab index diverged during \(context)"
                )
            }
            for (batchID, batch) in batchesByID {
                assert(batch.lease.id == batchID)
                switch batch.lease {
                case .replacement:
                    assert(batch.modelTransactionID == nil)
                case .retirement:
                    assert(batch.modelTransactionID != nil)
                }
                for tabID in batch.entriesByTabID.keys {
                    assert(
                        batchIDByTabID[tabID] == batchID,
                        "Transition batch index diverged during \(context)"
                    )
                }
            }
        #else
            _ = context
        #endif
    }
}

struct WebViewPlacementFingerprint: Equatable {
    let generation: UInt64
    let parkedWebViewID: ObjectIdentifier?
    let untrackedWebViewID: ObjectIdentifier?
    let primaryWindowID: UUID?
    let windowWebViewIDs: [UUID: ObjectIdentifier]

    init(_ snapshot: WebViewSessionSnapshot) {
        generation = snapshot.generation
        parkedWebViewID = snapshot.parkedWebView.map(ObjectIdentifier.init)
        untrackedWebViewID = snapshot.untrackedWebView.map(ObjectIdentifier.init)
        primaryWindowID = snapshot.primaryWindowID
        windowWebViewIDs = snapshot.windowWebViews.mapValues(
            ObjectIdentifier.init
        )
    }

    func matches(_ snapshot: WebViewSessionSnapshot) -> Bool {
        self == WebViewPlacementFingerprint(snapshot)
    }
}
