import SumiWebRuntime

@MainActor
final class ShortcutLiveRuntimeRetirementStaging {
    enum StageOutcome {
        case staged(ShortcutLiveRuntimeRetirementStage)
        case cleanup(ShortcutLiveRuntimeRetirementDrain)
        case terminal, conflicted
    }

    private let plan: ShortcutLiveTabRetirementPlan
    private let residence: ShortcutLiveResidenceRetirementParticipant
    private let leases: ShortcutLiveRuntimeRetirementLeaseOwner
    private let claims: ShortcutLiveRuntimeRetirementClaimSettlement

    init?(
        plan: ShortcutLiveTabRetirementPlan,
        residence: ShortcutLiveResidenceRetirementParticipant,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        self.residence = residence
        guard let leases = ShortcutLiveRuntimeRetirementLeaseOwner(
            plan: plan, residence: residence, teardown: teardown
        ) else { return nil }
        self.leases = leases
        claims = ShortcutLiveRuntimeRetirementClaimSettlement(
            plan: plan,
            residence: residence,
            leases: leases,
            teardown: teardown
        )
    }

    func stage() -> StageOutcome {
        guard residence.validateForStaging(),
              leases.terminalModelIsCurrent() else { return .conflicted }
        guard let tab = plan.entry?.tab else {
            return residence.stage() ? .staged(.none) : .conflicted
        }
        guard let runtime = plan.runtimeLease.registry else { return .conflicted }
        if tab.webViewSession.allKnownWebViews.isEmpty {
            guard let prepared = leases.prepareEmpty(tab: tab, runtime: runtime),
                  residence.stage() else { return .conflicted }
            return .staged(.empty(prepared))
        }
        return stageLeased(tab: tab, runtime: runtime)
    }

    func stagedModelIsExact(
        _ stage: ShortcutLiveRuntimeRetirementStage,
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        claims.stagedModelIsExact(stage, windowState: windowState)
    }

    func claim(
        _ stage: ShortcutLiveRuntimeRetirementStage,
        windowState: BrowserWindowShortcutMutationState?
    ) -> ShortcutLiveRuntimeRetirementSettlementOutcome {
        claims.claim(stage, windowState: windowState)
    }

    func claimedModelIsExact(
        _ effect: ShortcutLiveRuntimeRetirementEffect,
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        claims.claimedModelIsExact(effect, windowState: windowState)
    }

    func canAbandon(
        _ effect: ShortcutLiveRuntimeRetirementEffect,
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        claims.canAbandon(effect)
    }

    func rollback(_ stage: ShortcutLiveRuntimeRetirementStage) -> Bool {
        if case .leased(let batch) = stage {
            return leases.rollback(batch) && leases.cancelTerminalModel()
        }
        return residence.rollback() && leases.cancelTerminalModel()
    }

    func cancelPrepared() -> Bool {
        residence.cancelPrepared() && leases.cancelTerminalModel()
    }

    private func stageLeased(
        tab: Tab,
        runtime: RuntimePortRegistry
    ) -> StageOutcome {
        let receipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { [weak residence] in
                residence?.sourceModelIsExact() == true
            },
            commit: { [weak residence] in
                residence?.stage() == true
            },
            rollback: { [weak residence] in
                residence?.rollback() == true
            }
        )
        switch leases.beginLeased(tab: tab, runtime: runtime, receipt: receipt) {
        case .began(let batch):
            guard receipt.state == .modelStaged,
                  residence.stagedModelIsExact() else { return .conflicted }
            return .staged(.leased(batch))
        case .terminallyDrained:
            guard receipt.state == .modelStaged,
                  residence.stagedModelIsExact() else { return .conflicted }
            return .staged(.repositoryDrained(Set(plan.tabs.map(\.id))))
        case .modelConflict(let batch):
            return stageOutcome(
                leases.settleBeginModelConflict(batch, residence: residence)
            )
        case .modelValidationFailed, .rejected:
            return residence.compensateModelConflict()
                && leases.cancelTerminalModel() ? .terminal : .conflicted
        }
    }

    private func stageOutcome(
        _ outcome: ShortcutLiveRuntimeRetirementClaimOutcome
    ) -> StageOutcome {
        switch outcome {
        case .committedCleanup(let ownership),
                .conflictCleanup(let ownership):
            return .cleanup(claims.cleanupAfterConflict(ownership))
        case .restored:
            return .terminal
        case .claimed, .conflict:
            return .conflicted
        }
    }
}
