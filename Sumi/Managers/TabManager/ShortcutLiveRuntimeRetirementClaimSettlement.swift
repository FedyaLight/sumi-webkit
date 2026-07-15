@MainActor
final class ShortcutLiveRuntimeRetirementClaimSettlement {
    private let plan: ShortcutLiveTabRetirementPlan
    private let residence: ShortcutLiveResidenceRetirementParticipant
    private let leases: ShortcutLiveRuntimeRetirementLeaseOwner
    private let teardown: TabRuntimeTeardownService

    init(
        plan: ShortcutLiveTabRetirementPlan,
        residence: ShortcutLiveResidenceRetirementParticipant,
        leases: ShortcutLiveRuntimeRetirementLeaseOwner,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        self.residence = residence
        self.leases = leases
        self.teardown = teardown
    }

    func stagedModelIsExact(
        _ stage: ShortcutLiveRuntimeRetirementStage,
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        residence.stagedModelIsExact()
            && residence.runtimeAttachmentIsExact()
            && plan.windowIsCurrent(windowState)
            && leases.terminalModelIsCurrent()
            && leases.stagedModelIsExact(stage)
    }

    func claim(
        _ stage: ShortcutLiveRuntimeRetirementStage,
        windowState: BrowserWindowShortcutMutationState?
    ) -> ShortcutLiveRuntimeRetirementSettlementOutcome {
        guard stagedModelIsExact(stage, windowState: windowState),
              leases.claimTerminalModel() else {
            return settleUnclaimedStage(stage)
        }
        let effect: ShortcutLiveRuntimeRetirementEffect
        switch leases.claim(stage) {
        case .claimed(let claimed): effect = claimed
        case .committedCleanup(let ownership):
            return .cleanup(.retirement(publication(for: .committed(ownership))))
        case .conflictCleanup(let ownership):
            return .cleanup(rawCleanup(for: ownership))
        case .restored: return .restored
        case .conflict: return .conflict
        }
        let publication = publication(for: effect)
        guard claimedModelIsExact(effect, windowState: windowState),
              publication.canPublishNormally() else {
            if case .committed = effect {
                return .cleanup(.retirement(publication))
            }
            return .conflict
        }
        return .claimed(effect, publication)
    }

    func claimedModelIsExact(
        _ effect: ShortcutLiveRuntimeRetirementEffect,
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        residence.stagedModelIsExact()
            && plan.windowIsCurrent(windowState)
            && leases.terminalModelClaimIsExact()
            && claimedRuntimeIsExact(effect)
    }

    func canAbandon(
        _ effect: ShortcutLiveRuntimeRetirementEffect
    ) -> Bool {
        residence.stagedModelIsExact()
            && leases.terminalModelClaimIsExact()
            && leases.canAbandon(effect)
    }

    func cleanupAfterConflict(
        _ ownership: CommittedTabRuntimeRetirementCleanupOwnership
    ) -> ShortcutLiveRuntimeRetirementDrain {
        rawCleanup(for: ownership)
    }

    private func settleUnclaimedStage(
        _ stage: ShortcutLiveRuntimeRetirementStage
    ) -> ShortcutLiveRuntimeRetirementSettlementOutcome {
        switch stage {
        case .leased(let batch):
            switch leases.settleRollbackConflict(batch) {
            case .committedCleanup(let ownership),
                    .conflictCleanup(let ownership):
                return .cleanup(rawCleanup(for: ownership))
            case .restored: return .restored
            case .claimed, .conflict: return .conflict
            }
        case .none, .empty, .repositoryDrained:
            let restored = residence.rollback() && leases.cancelTerminalModel()
            return restored ? .restored : .conflict
        }
    }

    private func claimedRuntimeIsExact(
        _ effect: ShortcutLiveRuntimeRetirementEffect
    ) -> Bool {
        switch effect {
        case .terminallyDrained:
            return leases.claimedModelIsExact(effect)
        case .none, .empty, .committed:
            return residence.runtimeAttachmentIsExact()
                && leases.claimedModelIsExact(effect)
        }
    }

    private func publication(
        for effect: ShortcutLiveRuntimeRetirementEffect
    ) -> ShortcutLiveRuntimeRetirementPublication {
        leases.publication(residence: residence, effect: effect)
    }

    private func rawCleanup(
        for ownership: CommittedTabRuntimeRetirementCleanupOwnership
    ) -> ShortcutLiveRuntimeRetirementDrain {
        .cleanup { [teardown] in
            teardown.retirement.destroyAfterTerminalDrain(ownership)
        }
    }
}
