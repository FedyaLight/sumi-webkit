import Foundation
import WebKit

/// Coordinates the multi-store replacement transaction. The transaction store
/// keeps identity fingerprints, while active and retired generations remain
/// strongly owned by their respective canonical stores.
@MainActor
final class WebViewReplacementCoordinator {
    private typealias Placement = WebViewSessionPlacementStore.Entry
    private typealias Batch = WebViewReplacementTransactionStore.Batch
    private typealias Replacement =
        WebViewReplacementTransactionStore.Replacement

    private struct PreparedReplacement {
        let tabID: UUID
        let previous: WebViewSessionSnapshot
        let replacement: Placement
    }

    private enum PreparationResult {
        case prepared([PreparedReplacement])
        case rejected(WebViewReplacementBatchBeginResult)
    }

    private unowned let placements: WebViewSessionPlacementStore
    private unowned let transitions: WebViewOwnershipTransitionLedger
    private unowned let transactions: WebViewReplacementTransactionStore
    private unowned let validator: WebViewSessionConsistencyValidator

    init(
        placements: WebViewSessionPlacementStore,
        transitions: WebViewOwnershipTransitionLedger,
        transactions: WebViewReplacementTransactionStore,
        validator: WebViewSessionConsistencyValidator
    ) {
        self.placements = placements
        self.transitions = transitions
        self.transactions = transactions
        self.validator = validator
    }

    func begin(
        _ replacementEntries: [WebViewReplacementBatchEntry],
        validateModel: @MainActor () -> Bool,
        modelCommit: @MainActor () throws -> Void
    ) -> WebViewReplacementBatchBeginResult {
        let firstPreparation = prepare(replacementEntries)
        guard case .prepared = firstPreparation else {
            if case .rejected(let result) = firstPreparation { return result }
            preconditionFailure("Unreachable replacement preparation state")
        }
        guard validateModel() else { return .modelCommitFailed }

        let secondPreparation = prepare(replacementEntries)
        guard case .prepared(let prepared) = secondPreparation else {
            if case .rejected(let result) = secondPreparation { return result }
            preconditionFailure("Unreachable replacement preparation state")
        }

        let lease = WebViewReplacementBatchLease(id: UUID())
        let batch = apply(prepared, lease: lease)
        do {
            try modelCommit()
        } catch {
            guard conflict(in: batch) == nil else {
                preconditionFailure(
                    "Model commit mutated placement during replacement"
                )
            }
            _ = restore(batch)
            finish(batch)
            validator.assertConsistency("replacement.modelCommitFailed")
            return .modelCommitFailed
        }

        validator.assertConsistency("replacement.begin")
        return .began(lease)
    }

    func commit(
        _ lease: WebViewReplacementBatchLease
    ) -> WebViewReplacementBatchCommitResult {
        guard let batch = transactions.batch(for: lease) else {
            return .noLongerActive
        }
        if let conflict = conflict(in: batch) {
            return .conflict(
                tabID: conflict.tabID,
                currentGeneration: conflict.currentGeneration
            )
        }

        var retired: [UUID: WebViewSessionSnapshot] = [:]
        for (tabID, replacement) in batch.replacementsByTabID {
            guard let snapshot = transitions.takeRetirement(
                replacement.retirementLease
            ) else {
                preconditionFailure("Committed replacement lost retirement")
            }
            retired[tabID] = snapshot
        }
        bumpActiveGenerations(in: batch)
        finish(batch)
        validator.assertConsistency("replacement.commit")
        return .committed(retired: retired)
    }

    func rollback(
        _ lease: WebViewReplacementBatchLease,
        modelRollback: @MainActor () throws -> Void
    ) -> WebViewReplacementBatchRollbackResult {
        guard let batch = transactions.batch(for: lease) else {
            return .noLongerActive
        }
        if let conflict = conflict(in: batch) {
            return .conflict(
                tabID: conflict.tabID,
                currentGeneration: conflict.currentGeneration
            )
        }

        let discarded = restore(batch)
        do {
            try modelRollback()
        } catch {
            preconditionFailure(
                "Model rollback failed after placement restoration: \(error)"
            )
        }
        finish(batch)
        validator.assertConsistency("replacement.rollback")
        return .rolledBack(discarded: discarded)
    }

    private func prepare(
        _ requestedEntries: [WebViewReplacementBatchEntry]
    ) -> PreparationResult {
        guard !requestedEntries.isEmpty else {
            return .rejected(.invalid(tabID: nil))
        }
        let orderedEntries = requestedEntries.sorted {
            $0.tabID.uuidString < $1.tabID.uuidString
        }
        var seenTabIDs: Set<UUID> = []
        var replacementWebViewIDs: Set<ObjectIdentifier> = []
        var prepared: [PreparedReplacement] = []

        for requested in orderedEntries {
            guard seenTabIDs.insert(requested.tabID).inserted else {
                return .rejected(.invalid(tabID: requested.tabID))
            }
            guard !transactions.containsTransaction(for: requested.tabID),
                  !transitions.pendingCleanupTabIDs.contains(requested.tabID)
            else {
                return .rejected(.conflict(tabID: requested.tabID))
            }
            let currentGeneration = placements.generation(for: requested.tabID)
            guard currentGeneration == requested.expectedGeneration else {
                return .rejected(.stale(
                    tabID: requested.tabID,
                    currentGeneration: currentGeneration
                ))
            }

            let previous = placements.snapshot(for: requested.tabID)
            guard let replacement = replacementPlacement(
                for: requested,
                previous: previous
            ) else {
                return .rejected(.invalid(tabID: requested.tabID))
            }
            for webView in activeWebViews(in: replacement) {
                let webViewID = ObjectIdentifier(webView)
                guard replacementWebViewIDs.insert(webViewID).inserted,
                      residence(of: webView) == nil else {
                    return .rejected(.invalid(tabID: requested.tabID))
                }
            }
            prepared.append(PreparedReplacement(
                tabID: requested.tabID,
                previous: previous,
                replacement: replacement
            ))
        }
        return .prepared(prepared)
    }

    private func replacementPlacement(
        for requested: WebViewReplacementBatchEntry,
        previous: WebViewSessionSnapshot
    ) -> Placement? {
        var replacement = Placement()
        switch requested.placement {
        case .windowSet(let webViewsByWindowID, let primaryWindowID):
            guard !previous.windowWebViews.isEmpty,
                  !webViewsByWindowID.isEmpty,
                  webViewsByWindowID[primaryWindowID] != nil else {
                return nil
            }
            replacement.primaryWindowID = primaryWindowID
            replacement.windowWebViews = webViewsByWindowID
        case .detached(let webView, let residence):
            guard previous.windowWebViews.isEmpty,
                  previous.parkedWebView != nil
                    || previous.untrackedWebView != nil else { return nil }
            switch residence {
            case .parked:
                replacement.parkedWebView = webView
            case .untracked:
                replacement.untrackedWebView = webView
            }
        }
        return replacement
    }

    private func apply(
        _ prepared: [PreparedReplacement],
        lease: WebViewReplacementBatchLease
    ) -> Batch {
        transitions.openReplacementBatch(lease.id)
        var replacementsByTabID: [UUID: Replacement] = [:]
        for replacement in prepared {
            let retirementLease = WebViewRetirementLease(
                batchID: lease.id,
                tabID: replacement.tabID
            )
            placements.removeAllResidences(
                in: replacement.previous,
                tabID: replacement.tabID
            )
            transitions.retainRetirement(
                replacement.previous,
                lease: retirementLease
            )
            placements.storeMutated(
                replacement.replacement,
                for: replacement.tabID
            )
            placements.installActiveResidences(
                in: replacement.replacement,
                tabID: replacement.tabID
            )
            replacementsByTabID[replacement.tabID] = Replacement(
                retirementLease: retirementLease,
                installed: WebViewPlacementFingerprint(
                    placements.snapshot(for: replacement.tabID)
                )
            )
        }
        let batch = Batch(
            lease: lease,
            replacementsByTabID: replacementsByTabID
        )
        transactions.install(batch)
        return batch
    }

    private func conflict(
        in batch: Batch
    ) -> (tabID: UUID, currentGeneration: UInt64)? {
        for tabID in batch.replacementsByTabID.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let replacement = batch.replacementsByTabID[tabID] else {
                continue
            }
            let current = placements.snapshot(for: tabID)
            guard transactions.batchID(for: tabID) == batch.lease.id,
                  replacement.installed.matches(current),
                  transitions.retirementIsIntact(
                    replacement.retirementLease
                  ) else {
                return (tabID, current.generation)
            }
        }
        return nil
    }

    private func restore(_ batch: Batch) -> [UUID: WebViewSessionSnapshot] {
        var discarded: [UUID: WebViewSessionSnapshot] = [:]
        for tabID in batch.replacementsByTabID.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let replacement = batch.replacementsByTabID[tabID] else {
                continue
            }
            let current = placements.snapshot(for: tabID)
            discarded[tabID] = current
            placements.removeAllResidences(in: current, tabID: tabID)
            guard let previous = transitions.takeRetirement(
                replacement.retirementLease
            ) else {
                preconditionFailure("Rollback lost previous generation")
            }
            let restored = placements.entry(from: previous)
            placements.storeMutated(restored, for: tabID)
            placements.installActiveResidences(in: restored, tabID: tabID)
        }
        return discarded
    }

    private func bumpActiveGenerations(in batch: Batch) {
        for tabID in batch.replacementsByTabID.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            placements.storeMutated(
                placements.entry(for: tabID) ?? Placement(),
                for: tabID
            )
        }
    }

    private func finish(_ batch: Batch) {
        transactions.finish(batch)
        transitions.finishReplacementBatch(batch.lease.id)
    }

    private func residence(of webView: WKWebView) -> WebViewResidence? {
        let active = placements.residence(of: webView)
        let transition = transitions.residence(of: webView)
        assert(active == nil || transition == nil)
        return active ?? transition
    }

    private func activeWebViews(in placement: Placement) -> [WKWebView] {
        uniqueWebViews(
            Array(placement.windowWebViews.values)
                + [
                    placement.parkedWebView,
                    placement.untrackedWebView,
                ].compactMap(\.self)
        )
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        return webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }
}
