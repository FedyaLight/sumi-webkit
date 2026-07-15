import SumiWebRuntime

@MainActor
final class ShortcutLiveRuntimeRetirementLeaseOwner {
    private let plan: ShortcutLiveTabRetirementPlan
    private let teardown: TabRuntimeTeardownService
    private let terminalModel: PreparedTabTerminalModelRetirement?

    init?(
        plan: ShortcutLiveTabRetirementPlan,
        residence: ShortcutLiveResidenceRetirementParticipant,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        self.teardown = teardown
        if plan.tabs.isEmpty {
            terminalModel = nil
        } else {
            guard let prepared = teardown.terminalRetirement
                .prepareTerminalModelRetirement(
                    plan.tabs,
                    sourceModelIsExact: { [weak residence] in
                        residence?.terminalSourceModelIsExact() == true
                    }
                ) else { return nil }
            terminalModel = prepared
        }
    }

    func terminalModelIsCurrent() -> Bool {
        terminalModel?.isCurrent() ?? plan.tabs.isEmpty
    }

    func claimTerminalModel() -> Bool {
        terminalModel?.claimModel() ?? plan.tabs.isEmpty
    }

    func terminalModelClaimIsExact() -> Bool {
        terminalModel?.claimedModelIsExact() ?? plan.tabs.isEmpty
    }

    func cancelTerminalModel() -> Bool {
        terminalModel?.cancelPrepared() ?? true
    }

    func publication(
        residence: ShortcutLiveResidenceRetirementParticipant,
        effect: ShortcutLiveRuntimeRetirementEffect
    ) -> ShortcutLiveRuntimeRetirementPublication {
        ShortcutLiveRuntimeRetirementPublication(
            plan: plan,
            residence: residence,
            terminalModel: terminalModel,
            effect: effect,
            teardown: teardown
        )
    }

    func prepareEmpty(
        tab: Tab,
        runtime: RuntimePortRegistry
    ) -> PreparedTabRuntimeTeardown? {
        guard runtime.webViewLifecycle.canRetireTabWebViews([tab]) else {
            return nil
        }
        return PreparedTabRuntimeTeardown(tabs: [tab], runtime: runtime)
    }

    func beginLeased(
        tab: Tab,
        runtime: RuntimePortRegistry,
        receipt: WebViewRetirementModelTransactionReceipt
    ) -> TabRuntimeRetirementBeginOutcome {
        teardown.retirement.begin(
            tabs: [tab], using: runtime, modelTransaction: receipt
        )
    }

    func stagedModelIsExact(
        _ stage: ShortcutLiveRuntimeRetirementStage
    ) -> Bool {
        switch stage {
        case .none: return plan.entry == nil
        case .empty(let prepared):
            return exactTabs(prepared.tabs)
                && prepared.tabs.allSatisfy {
                    $0.webViewSession.allKnownWebViews.isEmpty
                }
                && prepared.runtime.webViewLifecycle
                    .canRetireTabWebViews(prepared.tabs)
        case .leased(let batch):
            return teardown.retirement.canCommit(batch)
        case .repositoryDrained:
            return plan.tabs.allSatisfy {
                $0.webViewSession.allKnownWebViews.isEmpty
            }
        }
    }

    func claim(
        _ stage: ShortcutLiveRuntimeRetirementStage
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        switch stage {
        case .none: return .claimed(.none)
        case .empty(let prepared): return .claimed(.empty(prepared))
        case .repositoryDrained(let tabIDs):
            return .claimed(.terminallyDrained(tabIDs))
        case .leased(let batch):
            switch teardown.retirement.commit(batch) {
            case .committed(let committed): return .claimed(.committed(committed))
            case .cleanupOnly(let ownership): return .committedCleanup(ownership)
            case .noLongerActive:
                return .claimed(.terminallyDrained(batch.runtimeTabIDs))
            case .conflict:
                return settleRollbackConflict(batch)
            }
        }
    }

    func claimedModelIsExact(
        _ effect: ShortcutLiveRuntimeRetirementEffect
    ) -> Bool {
        switch effect {
        case .none: return plan.entry == nil
        case .empty(let prepared):
            return exactTabs(prepared.tabs)
                && prepared.tabs.allSatisfy {
                    $0.webViewSession.allKnownWebViews.isEmpty
                }
        case .committed(let committed):
            return exactTabs(committed.tabs)
                && teardown.retirement.committedRetirementIsExact(committed)
        case .terminallyDrained:
            return plan.tabs.allSatisfy {
                $0.webViewSession.allKnownWebViews.isEmpty
            }
        }
    }

    func canAbandon(_ effect: ShortcutLiveRuntimeRetirementEffect) -> Bool {
        guard case .committed(let committed) = effect else { return true }
        return teardown.retirement.committedRetirementIsExact(committed)
    }

    func rollback(_ batch: TabRuntimeRetirementBatch) -> Bool {
        teardown.retirement.rollback(batch) == .rolledBack
    }

    func settleBeginModelConflict(
        _ batch: TabRuntimeRetirementBatch,
        residence: ShortcutLiveResidenceRetirementParticipant
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        ShortcutLiveRuntimeRetirementConflictSettlement.settleBegin(
            batch,
            residence: residence,
            retirement: teardown.retirement,
            terminalModel: terminalModel
        )
    }

    func settleRollbackConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        ShortcutLiveRuntimeRetirementConflictSettlement.settleRollback(
            batch,
            retirement: teardown.retirement,
            terminalModel: terminalModel
        )
    }

    private func exactTabs(_ tabs: [Tab]) -> Bool {
        tabs.count == plan.tabs.count
            && zip(tabs, plan.tabs).allSatisfy { $0 === $1 }
    }
}
