import Foundation
import WebKit

/// Coordinates replacement and pure-retirement transactions across the
/// canonical placement, transition, and identity stores.
@MainActor
final class WebViewSessionTransitionCoordinator {
    private typealias Placement = WebViewSessionPlacementStore.Entry
    private typealias Batch = WebViewSessionTransitionTransactionStore.Batch
    private typealias BatchLease =
        WebViewSessionTransitionTransactionStore.BatchLease
    private typealias TransactionEntry =
        WebViewSessionTransitionTransactionStore.Entry

    private struct PreparedReplacement {
        let tabID: UUID
        let previous: WebViewSessionSnapshot
        let replacement: Placement
    }

    private enum PreparationResult {
        case prepared([PreparedReplacement])
        case rejected(WebViewReplacementBatchBeginResult)
    }

    private enum RetirementPreparationResult {
        case prepared([PreparedReplacement])
        case rejected(WebViewRetirementBatchBeginResult)
    }

    private unowned let placements: WebViewSessionPlacementStore
    private unowned let transitions: WebViewOwnershipTransitionLedger
    private unowned let transactions: WebViewSessionTransitionTransactionStore
    private unowned let validator: WebViewSessionConsistencyValidator

    init(
        placements: WebViewSessionPlacementStore,
        transitions: WebViewOwnershipTransitionLedger,
        transactions: WebViewSessionTransitionTransactionStore,
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
        modelCommit: @MainActor () throws -> Void,
        modelRollback: @MainActor () throws -> Void
    ) -> WebViewReplacementBatchBeginResult {
        let firstPreparation = prepare(replacementEntries)
        guard case .prepared = firstPreparation else {
            if case .rejected(let result) = firstPreparation { return result }
            preconditionFailure("Unreachable replacement preparation state")
        }
        guard validateModel() else {
            return .modelValidationFailed
        }

        let secondPreparation = prepare(replacementEntries)
        guard case .prepared(let prepared) = secondPreparation else {
            if case .rejected(let result) = secondPreparation { return result }
            preconditionFailure("Unreachable replacement preparation state")
        }

        let lease = WebViewReplacementBatchLease(id: UUID())
        let batch = apply(
            prepared,
            lease: .replacement(lease),
            modelTransactionID: nil
        )
        do {
            try modelCommit()
        } catch {
            guard transactions.batch(for: lease) != nil else {
                validator.assertConsistency("replacement.modelCommitDrained")
                return .noLongerActive
            }
            guard transactions.claimReplacementRollback(for: lease) != nil
            else {
                validator.assertConsistency(
                    "replacement.modelCommitRollbackDrained"
                )
                return .noLongerActive
            }
            guard conflict(in: batch) == nil else {
                validator.assertConsistency(
                    "replacement.modelCommitRollbackConflict"
                )
                return .modelRollbackFailed(lease)
            }
            do {
                try modelRollback()
            } catch {
                guard transactions.rollingBackBatch(for: lease) != nil else {
                    validator.assertConsistency(
                        "replacement.modelCommitRollbackDrained"
                    )
                    return .noLongerActive
                }
                validator.assertConsistency(
                    "replacement.modelCommitRollbackFailed"
                )
                return .modelRollbackFailed(lease)
            }
            guard let current = transactions.rollingBackBatch(for: lease)
            else {
                validator.assertConsistency(
                    "replacement.modelCommitRollbackDrained"
                )
                return .noLongerActive
            }
            guard conflict(in: current) == nil else {
                validator.assertConsistency(
                    "replacement.modelCommitRollbackConflict"
                )
                return .modelRollbackFailed(lease)
            }
            let discarded = restore(current)
            finish(current)
            validator.assertConsistency("replacement.modelCommitFailed")
            return .modelCommitFailed(discarded: discarded)
        }
        guard transactions.batch(for: lease) != nil else {
            validator.assertConsistency("replacement.modelCommitDrained")
            return .noLongerActive
        }

        validator.assertConsistency("replacement.begin")
        return .began(lease)
    }

    func beginRetirement(
        _ retirementEntries: [WebViewRetirementBatchEntry],
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> WebViewRetirementBatchBeginResult {
        let firstPreparation = prepareRetirement(retirementEntries)
        guard case .prepared = firstPreparation else {
            if case .rejected(let result) = firstPreparation { return result }
            preconditionFailure("Unreachable retirement preparation state")
        }
        guard modelTransaction.isCurrent() else {
            return .modelValidationFailed
        }

        let secondPreparation = prepareRetirement(retirementEntries)
        guard case .prepared(let prepared) = secondPreparation else {
            if case .rejected(let result) = secondPreparation { return result }
            preconditionFailure("Unreachable retirement preparation state")
        }

        let lease = WebViewRetirementBatchLease(id: UUID())
        _ = apply(
            prepared,
            lease: .retirement(lease),
            modelTransactionID: modelTransaction.id
        )
        modelTransaction.commit()
        guard transactions.batch(for: lease) != nil else {
            validator.assertConsistency("retirement.commitDrained")
            return .noLongerActive
        }

        validator.assertConsistency("retirement.begin")
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
        for (tabID, replacement) in batch.entriesByTabID {
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

        guard transactions.claimReplacementRollback(for: lease) != nil else {
            return .noLongerActive
        }
        do {
            try modelRollback()
        } catch {
            guard transactions.rollingBackBatch(for: lease) != nil else {
                validator.assertConsistency("replacement.rollbackDrained")
                return .terminallyDrained
            }
            validator.assertConsistency("replacement.modelRollbackFailed")
            return .modelRollbackFailed
        }
        guard let current = transactions.rollingBackBatch(for: lease) else {
            validator.assertConsistency("replacement.rollbackDrained")
            return .terminallyDrained
        }
        if let conflict = conflict(in: current) {
            return .conflict(
                tabID: conflict.tabID,
                currentGeneration: conflict.currentGeneration
            )
        }
        let discarded = restore(current)
        finish(current)
        validator.assertConsistency("replacement.rollback")
        return .rolledBack(discarded: discarded)
    }

    func commitRetirement(
        _ lease: WebViewRetirementBatchLease
    ) -> WebViewRetirementBatchCommitResult {
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
        for (tabID, entry) in batch.entriesByTabID {
            guard let snapshot = transitions.retirementSnapshot(
                for: entry.retirementLease
            ) else {
                return .conflict(
                    tabID: tabID,
                    currentGeneration: placements.generation(for: tabID)
                )
            }
            retired[tabID] = snapshot
        }
        for tabID in orderedTabIDs(in: batch) {
            guard let entry = batch.entriesByTabID[tabID],
                  transitions.takeRetirement(entry.retirementLease) != nil
            else {
                preconditionFailure("Current retirement lost its snapshot")
            }
            placements.removeRetirementReservation(for: tabID)
        }
        finish(batch)
        validator.assertConsistency("retirement.commit")
        return .committed(retired: retired)
    }

    func canCommitRetirement(
        _ lease: WebViewRetirementBatchLease
    ) -> Bool {
        guard let batch = transactions.batch(for: lease) else { return false }
        return conflict(in: batch) == nil
    }

    func rollbackRetirement(
        _ lease: WebViewRetirementBatchLease,
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> WebViewRetirementBatchRollbackResult {
        guard let batch = transactions.batch(for: lease) else {
            return .noLongerActive
        }
        guard batch.modelTransactionID == modelTransaction.id else {
            return .modelTransactionMismatch
        }
        if let conflict = conflict(in: batch) {
            return .conflict(
                tabID: conflict.tabID,
                currentGeneration: conflict.currentGeneration
            )
        }
        guard transactions.claimRetirementRollback(for: lease) != nil else {
            return .noLongerActive
        }

        modelTransaction.rollback()
        guard let currentBatch = transactions.rollingBackBatch(
            for: lease
        ) else {
            validator.assertConsistency("retirement.rollbackDrained")
            return .noLongerActive
        }
        guard currentBatch.modelTransactionID == modelTransaction.id else {
            return .modelTransactionMismatch
        }
        if let conflict = conflict(in: currentBatch) {
            return .conflict(
                tabID: conflict.tabID,
                currentGeneration: conflict.currentGeneration
            )
        }
        restoreRetirement(currentBatch)
        finish(currentBatch)
        validator.assertConsistency("retirement.rollback")
        return .rolledBack
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

    private func prepareRetirement(
        _ requestedEntries: [WebViewRetirementBatchEntry]
    ) -> RetirementPreparationResult {
        guard !requestedEntries.isEmpty else {
            return .rejected(.invalid(tabID: nil))
        }
        let orderedEntries = requestedEntries.sorted {
            $0.tabID.uuidString < $1.tabID.uuidString
        }
        var seenTabIDs: Set<UUID> = []
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
            guard !previous.allKnownWebViews.isEmpty else {
                return .rejected(.invalid(tabID: requested.tabID))
            }
            prepared.append(PreparedReplacement(
                tabID: requested.tabID,
                previous: previous,
                replacement: Placement()
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
        lease: BatchLease,
        modelTransactionID: UUID?
    ) -> Batch {
        transitions.openTransactionBatch(lease.id)
        var entriesByTabID: [UUID: TransactionEntry] = [:]
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
            switch lease {
            case .replacement:
                placements.storeMutated(
                    replacement.replacement,
                    for: replacement.tabID
                )
                placements.installActiveResidences(
                    in: replacement.replacement,
                    tabID: replacement.tabID
                )
            case .retirement:
                precondition(replacement.replacement.isEmpty)
                placements.installRetirementReservation(
                    for: replacement.tabID
                )
            }
            entriesByTabID[replacement.tabID] = TransactionEntry(
                retirementLease: retirementLease,
                installed: WebViewPlacementFingerprint(
                    placements.snapshot(for: replacement.tabID)
                )
            )
        }
        let batch = Batch(
            lease: lease,
            entriesByTabID: entriesByTabID,
            modelTransactionID: modelTransactionID
        )
        transactions.install(batch)
        return batch
    }

    private func conflict(
        in batch: Batch
    ) -> (tabID: UUID, currentGeneration: UInt64)? {
        for tabID in orderedTabIDs(in: batch) {
            guard let replacement = batch.entriesByTabID[tabID] else {
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
        for tabID in orderedTabIDs(in: batch) {
            guard let replacement = batch.entriesByTabID[tabID] else {
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

    private func restoreRetirement(_ batch: Batch) {
        for tabID in orderedTabIDs(in: batch) {
            guard let entry = batch.entriesByTabID[tabID],
                  let previous = transitions.takeRetirement(
                      entry.retirementLease
                  ) else {
                preconditionFailure("Rollback lost retired generation")
            }
            placements.restoreExactly(previous, for: tabID)
        }
    }

    private func bumpActiveGenerations(in batch: Batch) {
        for tabID in orderedTabIDs(in: batch) {
            placements.storeMutated(
                placements.entry(for: tabID) ?? Placement(),
                for: tabID
            )
        }
    }

    private func finish(_ batch: Batch) {
        transactions.finish(batch)
        transitions.finishTransactionBatch(batch.lease.id)
    }

    private func orderedTabIDs(in batch: Batch) -> [UUID] {
        batch.entriesByTabID.keys.sorted {
            $0.uuidString < $1.uuidString
        }
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
