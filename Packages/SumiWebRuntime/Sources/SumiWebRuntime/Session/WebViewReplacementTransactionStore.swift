import Foundation

/// Identity-only record of installed replacement transactions. Previous
/// generations are strongly owned only by `WebViewOwnershipTransitionLedger`;
/// active generations are strongly owned only by the placement store.
@MainActor
final class WebViewReplacementTransactionStore {
    struct Replacement {
        let retirementLease: WebViewRetirementLease
        let installed: WebViewPlacementFingerprint
    }

    struct Batch {
        let lease: WebViewReplacementBatchLease
        let replacementsByTabID: [UUID: Replacement]
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
        guard let batch = batchesByID[lease.id], batch.lease == lease else {
            return nil
        }
        return batch
    }

    func install(_ batch: Batch) {
        precondition(batchesByID[batch.lease.id] == nil)
        for tabID in batch.replacementsByTabID.keys {
            precondition(batchIDByTabID[tabID] == nil)
        }
        batchesByID[batch.lease.id] = batch
        for tabID in batch.replacementsByTabID.keys {
            batchIDByTabID[tabID] = batch.lease.id
        }
    }

    func finish(_ batch: Batch) {
        if batchesByID[batch.lease.id]?.lease == batch.lease {
            batchesByID.removeValue(forKey: batch.lease.id)
        }
        for tabID in batch.replacementsByTabID.keys
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
                    batchesByID[batchID]?.replacementsByTabID[tabID] != nil,
                    "Replacement tab index diverged during \(context)"
                )
            }
            for (batchID, batch) in batchesByID {
                assert(batch.lease.id == batchID)
                for tabID in batch.replacementsByTabID.keys {
                    assert(
                        batchIDByTabID[tabID] == batchID,
                        "Replacement batch index diverged during \(context)"
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
