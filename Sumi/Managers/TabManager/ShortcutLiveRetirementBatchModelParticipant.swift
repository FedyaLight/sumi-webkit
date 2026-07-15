import Foundation

@MainActor
final class ShortcutLiveRetirementBatchModelParticipant {
    private enum State { case prepared, residenceStaged, staged, claimed, terminal }

    private let plan: ShortcutLiveRetirementBatchPlan
    private let structural: ShortcutLiveRetirementBatchStructuralParticipant
    private var terminalModel: PreparedTabTerminalModelRetirement?
    private var residenceChanges: [LiveShortcutResidenceMutationStaging.Change] = []
    private var state = State.prepared

    init?(
        plan: ShortcutLiveRetirementBatchPlan,
        windowMutations: BrowserWindowShortcutMutationOwner,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        guard let structural = ShortcutLiveRetirementBatchStructuralParticipant(
            plan: plan, windowMutations: windowMutations
        ) else { return nil }
        self.structural = structural
        terminalModel = nil
        if plan.tabs.isEmpty == false {
            terminalModel = teardown.terminalRetirement
                .prepareTerminalModelRetirement(
                    plan.tabs,
                    sourceModelIsExact: { [weak self] in
                        self?.terminalSourceIsExact() == true
                    }
                )
            guard terminalModel != nil else {
                _ = structural.cancelPrepared()
                return nil
            }
        }
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return plan.sourceIsExact()
            && structural.isCurrent()
            && terminalModel?.isCurrent() != false
    }

    func stageResidence() -> Bool {
        guard isCurrent(),
              let changes = plan.registry.staging.stage(plan.residencePlans)
        else { return false }
        residenceChanges = changes
        state = .residenceStaged
        return true
    }

    func rollbackResidence() -> Bool {
        let returnsToPrepared: Bool
        switch state {
        case .residenceStaged: returnsToPrepared = true
        case .staged, .claimed: returnsToPrepared = false
        case .prepared: return residenceChanges.isEmpty
        case .terminal: return false
        }
        guard residenceChanges.isEmpty
                || plan.registry.staging.rollback(residenceChanges)
        else { return false }
        residenceChanges.removeAll()
        if returnsToPrepared { state = .prepared }
        return true
    }

    func stageWindows() -> Bool {
        guard case .residenceStaged = state,
              residenceAndAttachmentAreExact(),
              structural.stage() else { return false }
        state = .staged
        return stagedModelIsExact()
    }

    func claim() -> Bool {
        guard stagedModelIsExact(), terminalModel?.claimModel() != false else {
            return false
        }
        state = .claimed
        return claimedModelAndAttachmentAreExact()
    }

    func commitSilentModel() -> ShortcutLiveRetirementBatchResidencePublication {
        guard claimedModelIsExact() else {
            preconditionFailure("Shortcut batch model was not claimed")
        }
        var residencePublication: ShortcutLiveRetirementBatchResidencePublication?
        let commitResidence = { [self] in
            residencePublication = ShortcutLiveRetirementBatchResidencePublication(
                registry: plan.registry,
                changes: residenceChanges
            )
        }
        if let terminalModel {
            precondition(terminalModel.commitSilentModel(
                after: commitResidence
            ))
        } else {
            commitResidence()
        }
        state = .terminal
        guard let residencePublication else {
            preconditionFailure("Shortcut residence publication was not retained")
        }
        return residencePublication
    }

    func publishWindows() {
        guard case .terminal = state else {
            preconditionFailure("Shortcut terminal model was not committed")
        }
        structural.publish()
    }

    func cancelBeforeRuntimeCommit() -> Bool {
        let structuralRestored: Bool
        switch state {
        case .prepared, .residenceStaged:
            structuralRestored = structural.cancelPrepared()
        case .staged, .claimed:
            structuralRestored = structural.rollback()
        case .terminal:
            return false
        }
        let residenceRestored = rollbackResidence()
        let terminalRestored = terminalModel?.cancelPrepared() ?? true
        state = .terminal
        return structuralRestored && residenceRestored && terminalRestored
    }

    var terminalReceipt: PreparedTabTerminalModelRetirement? { terminalModel }

    private func terminalSourceIsExact() -> Bool {
        switch state {
        case .prepared: return plan.sourceIsExact()
        case .residenceStaged, .staged:
            return residenceAndAttachmentAreExact()
        case .claimed: return residenceIsExact()
        case .terminal: return false
        }
    }

    private func residenceAndAttachmentAreExact() -> Bool {
        plan.attachment.isCurrent() && residenceIsExact()
    }

    private func residenceIsExact() -> Bool {
        plan.registry.staging.canPublish(residenceChanges)
    }

    private func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return residenceAndAttachmentAreExact()
            && structural.isCurrent()
    }

    func claimedModelAndAttachmentAreExact() -> Bool {
        plan.attachment.isCurrent() && claimedModelIsExact()
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return residenceIsExact()
            && structural.isCurrent()
            && terminalModel?.claimedModelIsExact() != false
    }
}
