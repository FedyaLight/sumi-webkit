import Foundation
import SumiWebRuntime

enum TabRuntimeRetirementRejection: Equatable {
    case stale(tabID: UUID, currentGeneration: UInt64)
    case conflict(tabID: UUID)
    case invalid(tabID: UUID?)
    case protected
}

enum TabRuntimeRetirementBeginOutcome {
    case began(TabRuntimeRetirementBatch)
    case modelValidationFailed
    case modelConflict(TabRuntimeRetirementBatch)
    case terminallyDrained
    case rejected(TabRuntimeRetirementRejection)
}

enum TabRuntimeRetirementCommitOutcome {
    case committed(CommittedTabRuntimeRetirementCleanupOwnership)
    case cleanupOnly(CommittedTabRuntimeRetirementCleanupOwnership)
    case noLongerActive
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

enum TabRuntimeRetirementRollbackOutcome: Equatable {
    case rolledBack
    case noLongerActive
    case modelTransactionMismatch
    case modelConflict
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

enum TabRuntimeRetirementCleanupClaimOutcome {
    case claimed(CommittedTabRuntimeRetirementCleanupOwnership)
    case noLongerActive
}

@MainActor
struct TabRuntimeRetirementBatch {
    let tabs: [Tab]
    let runtimeTabIDs: Set<UUID>
    let runtime: RuntimePortRegistry
    let lease: WebViewRetirementBatchLease
    let modelTransaction: WebViewRetirementModelTransactionReceipt
}

/// Owns the exact repository lease and model receipt for reversible pure
/// retirement. Physical destruction is permitted only after lease commit.
@MainActor
final class TabRuntimeRetirementService {
    private let webViewSessions: WebViewSessionRepository
    private let publisher: TabRuntimeTeardownPublisher

    init(
        webViewSessions: WebViewSessionRepository,
        publisher: TabRuntimeTeardownPublisher
    ) {
        self.webViewSessions = webViewSessions
        self.publisher = publisher
    }

    func begin(
        tabs: [Tab],
        using runtime: RuntimePortRegistry,
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> TabRuntimeRetirementBeginOutcome {
        guard tabs.isEmpty == false else {
            return .rejected(.invalid(tabID: nil))
        }
        var seenTabIDs = Set<UUID>()
        guard let duplicate = tabs.first(where: {
            seenTabIDs.insert($0.id).inserted == false
        }) else {
            return beginUnique(
                tabs: tabs,
                runtime: runtime,
                modelTransaction: modelTransaction
            )
        }
        return .rejected(.invalid(tabID: duplicate.id))
    }

    private func beginUnique(
        tabs: [Tab],
        runtime: RuntimePortRegistry,
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> TabRuntimeRetirementBeginOutcome {
        let tabs = tabs.sorted { Self.uuidOrder($0.id, $1.id) }
        let liveTabs = tabs.filter {
            $0.webViewSession.allKnownWebViews.isEmpty == false
        }
        guard liveTabs.isEmpty == false else {
            return .rejected(.invalid(tabID: nil))
        }
        guard let unbacked = liveTabs.first(where: {
            $0.webViewSession.isBacked(by: webViewSessions) == false
        }) else {
            return beginBacked(
                tabs: tabs,
                liveTabs: liveTabs,
                runtime: runtime,
                modelTransaction: modelTransaction
            )
        }
        return .rejected(.invalid(tabID: unbacked.id))
    }

    func commit(
        _ batch: TabRuntimeRetirementBatch
    ) -> TabRuntimeRetirementCommitOutcome {
        switch webViewSessions.commitRetirementBatch(batch.lease) {
        case .committed(let retired):
            precondition(
                Set(retired.keys) == batch.runtimeTabIDs,
                "Retirement commit returned a different Tab generation set"
            )
            let generations = retired.keys.sorted(by: Self.uuidOrder).map {
                RetiredTabWebViewGeneration(tabID: $0, snapshot: retired[$0]!)
            }
            guard batch.runtime.webViewLifecycle
                .beginCommittedTabRetirement(batch.tabs) else {
                return .cleanupOnly(
                    CommittedTabRuntimeRetirementCleanupOwnership(
                        tabs: batch.tabs,
                        runtime: batch.runtime,
                        generations: generations,
                        completionPolicy: .drainOnly
                    )
                )
            }
            return .committed(
                CommittedTabRuntimeRetirementCleanupOwnership(
                    tabs: batch.tabs,
                    runtime: batch.runtime,
                    generations: generations,
                    completionPolicy: .normalOrDrain
                )
            )
        case .noLongerActive:
            return .noLongerActive
        case .conflict(let tabID, let generation):
            return .conflict(tabID: tabID, currentGeneration: generation)
        }
    }

    func canCommit(_ batch: TabRuntimeRetirementBatch) -> Bool {
        batch.runtime.webViewLifecycle.canRetireTabWebViews(batch.tabs)
            && webViewSessions.canCommitRetirementBatch(batch.lease)
    }

    func claimNormalRuntimePublication(
        _ committed: CommittedTabRuntimeRetirementCleanupOwnership
    ) -> ClaimedCommittedTabRuntimeRetirementCleanup? {
        committed.claimNormalCompletion()
    }

    @discardableResult
    func publishClaimedRuntime(
        _ claimed: ClaimedCommittedTabRuntimeRetirementCleanup,
        beforeDestruction: (RuntimePortRegistry) -> Void
    ) -> Set<UUID> {
        guard let effect = claimed.takeNormalEffect() else { return [] }
        let published = publisher.publishRuntime(
            effect.tabs,
            runtime: effect.runtime
        )
        beforeDestruction(effect.runtime)
        effect.runtime.webViewLifecycle.destroyRetiredWebViews(
            effect.generations,
            completingRetirementOf: effect.tabs
        )
        return published
    }

    func destroyCommittedRuntime(
        _ committed: CommittedTabRuntimeRetirementCleanupOwnership
    ) {
        guard let claimed = committed.claimNormalCompletion() else { return }
        destroyClaimedRuntime(claimed)
    }

    func destroyClaimedRuntime(
        _ claimed: ClaimedCommittedTabRuntimeRetirementCleanup
    ) {
        guard let effect = claimed.takeNormalEffect() else { return }
        effect.runtime.webViewLifecycle.destroyRetiredWebViews(
            effect.generations,
            completingRetirementOf: effect.tabs
        )
    }

    func committedRetirementIsExact(
        _ committed: CommittedTabRuntimeRetirementCleanupOwnership
    ) -> Bool {
        let tabs = committed.tabs
        return committed.isOwned
            && Set(tabs.map(\.id)) == Set(committed.generations.map(\.tabID))
            && tabs.allSatisfy {
                $0.webViewSession.allKnownWebViews.isEmpty
            }
            && committed.runtime.webViewLifecycle
                .committedTabRetirementIsExact(tabs)
    }

    func destroyAfterTerminalDrain(
        _ committed: CommittedTabRuntimeRetirementCleanupOwnership
    ) {
        guard let claimed = committed.claimAggregateDrainCompletion() else {
            return
        }
        destroyClaimedAfterTerminalDrain(claimed)
    }

    func destroyClaimedAfterTerminalDrain(
        _ claimed: ClaimedCommittedTabRuntimeRetirementCleanup
    ) {
        guard let effect = claimed.takeTerminalDrainEffect() else { return }
        effect.runtime.webViewLifecycle.destroyTerminallyDrainedRetiredWebViews(
            effect.generations,
            belongingTo: effect.tabs
        )
    }

    func rollback(
        _ batch: TabRuntimeRetirementBatch
    ) -> TabRuntimeRetirementRollbackOutcome {
        switch webViewSessions.rollbackRetirementBatch(
            batch.lease,
            modelTransaction: batch.modelTransaction
        ) {
        case .rolledBack:
            return .rolledBack
        case .noLongerActive:
            return .noLongerActive
        case .modelTransactionMismatch:
            return .modelTransactionMismatch
        case .modelConflict:
            return .modelConflict
        case .conflict(let tabID, let generation):
            return .conflict(tabID: tabID, currentGeneration: generation)
        }
    }

    func restoreAfterModelCompensation(
        _ batch: TabRuntimeRetirementBatch
    ) -> TabRuntimeRetirementRollbackOutcome {
        switch webViewSessions.restoreRetirementAfterModelCompensation(
            batch.lease
        ) {
        case .restored:
            return .rolledBack
        case .noLongerActive:
            return .noLongerActive
        case .conflict(let tabID, let generation):
            return .conflict(tabID: tabID, currentGeneration: generation)
        }
    }

    func claimCleanupAfterModelConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> TabRuntimeRetirementCleanupClaimOutcome {
        switch webViewSessions.claimRetirementCleanup(batch.lease) {
        case .claimed(let retired):
            let generations = retired.keys.sorted(by: Self.uuidOrder).map {
                RetiredTabWebViewGeneration(tabID: $0, snapshot: retired[$0]!)
            }
            let ownership = CommittedTabRuntimeRetirementCleanupOwnership(
                tabs: batch.tabs,
                runtime: batch.runtime,
                generations: generations,
                completionPolicy: .drainOnly
            )
            return .claimed(ownership)
        case .noLongerActive:
            return .noLongerActive
        }
    }

    private func beginBacked(
        tabs: [Tab],
        liveTabs: [Tab],
        runtime: RuntimePortRegistry,
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> TabRuntimeRetirementBeginOutcome {
        guard runtime.webViewLifecycle.canRetireTabWebViews(tabs) else {
            return .rejected(.protected)
        }
        let entries = liveTabs.map {
            WebViewRetirementBatchEntry(
                tabID: $0.id,
                expectedGeneration: $0.webViewSession.generation
            )
        }
        switch webViewSessions.beginRetirementBatch(
            entries,
            modelTransaction: modelTransaction
        ) {
        case .began(let lease):
            return .began(TabRuntimeRetirementBatch(
                tabs: tabs,
                runtimeTabIDs: Set(liveTabs.map(\.id)),
                runtime: runtime,
                lease: lease,
                modelTransaction: modelTransaction
            ))
        case .stale(let tabID, let generation):
            return .rejected(.stale(
                tabID: tabID,
                currentGeneration: generation
            ))
        case .conflict(let tabID):
            return .rejected(.conflict(tabID: tabID))
        case .invalid(let tabID):
            return .rejected(.invalid(tabID: tabID))
        case .modelValidationFailed:
            return .modelValidationFailed
        case .modelConflict(let lease):
            return .modelConflict(TabRuntimeRetirementBatch(
                tabs: tabs,
                runtimeTabIDs: Set(liveTabs.map(\.id)),
                runtime: runtime,
                lease: lease,
                modelTransaction: modelTransaction
            ))
        case .noLongerActive:
            return .terminallyDrained
        }
    }

    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
