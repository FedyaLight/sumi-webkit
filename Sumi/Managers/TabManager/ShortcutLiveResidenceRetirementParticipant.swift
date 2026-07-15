@MainActor
final class ShortcutLiveResidenceRetirementParticipant {
    private enum State { case prepared, staged, terminal }

    private let plan: ShortcutLiveTabRetirementPlan
    private var change: LiveShortcutResidenceMutationStaging.Change?
    private var state = State.prepared

    init(plan: ShortcutLiveTabRetirementPlan) { self.plan = plan }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return sourceModelIsExact() && runtimeAttachmentIsExact()
    }

    func sourceModelIsExact() -> Bool {
        guard let entry = plan.entry else {
            return plan.registry.tab(for: plan.pinID, in: plan.windowID) == nil
        }
        return plan.residencePlan != nil
            && plan.registry.entry(containing: entry.tab)?.isIdentical(to: entry)
                == true
    }

    func runtimeAttachmentIsExact() -> Bool {
        plan.runtimeConnection.accepts(plan.runtimeLease)
    }

    func stage() -> Bool {
        guard validateForStaging() else { return false }
        if let residencePlan = plan.residencePlan {
            guard let staged = plan.registry.staging.stage([residencePlan])?.first
            else { return false }
            change = staged
        }
        state = .staged
        return stagedModelIsExact()
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        if let change { return plan.registry.staging.canPublish([change]) }
        return plan.registry.tab(for: plan.pinID, in: plan.windowID) == nil
    }

    func terminalSourceModelIsExact() -> Bool {
        switch state {
        case .prepared: return sourceModelIsExact()
        case .staged: return stagedModelIsExact()
        case .terminal: return false
        }
    }

    func compensateModelConflict() -> Bool {
        switch state {
        case .prepared: return cancelPrepared()
        case .staged: return rollback()
        case .terminal: return false
        }
    }

    func rollback() -> Bool {
        guard case .staged = state else { return false }
        if let change, plan.registry.staging.rollback([change]) == false {
            return false
        }
        state = .terminal
        return true
    }

    func commitSilentModel() -> PreparedShortcutLiveResidencePublication {
        guard stagedModelIsExact() else {
            preconditionFailure("Shortcut residence retirement lost model")
        }
        state = .terminal
        return PreparedShortcutLiveResidencePublication(
            registry: plan.registry, change: change
        )
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .terminal
        return true
    }

    func abandonForTerminalDrain() {
        _ = commitSilentModel()
    }
}
