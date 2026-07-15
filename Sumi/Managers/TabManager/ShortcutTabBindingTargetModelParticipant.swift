@MainActor
final class ShortcutTabBindingTargetModelParticipant {
    enum StageOutcome { case staged, restored, conflicted }
    private enum State { case prepared, staged, published, terminal, conflicted }

    private let inputs: [ShortcutTabBindingModelTransaction.Input]
    private let residences: any ShortcutTabBindingResidenceTransaction
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private let profiles: TabProfileTransitionService
    private var state = State.prepared

    var exactTabs: [Tab] { inputs.flatMap(\.plans).map(\.tab) }

    init(
        inputs: [ShortcutTabBindingModelTransaction.Input],
        residences: any ShortcutTabBindingResidenceTransaction,
        runtimeConnection: TabRuntimePortConnection,
        runtimeLease: TabRuntimePortLease,
        profiles: TabProfileTransitionService
    ) {
        self.inputs = inputs
        self.residences = residences
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        self.profiles = profiles
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return residences.validateForStaging()
            && runtimeConnection.acceptsExactAttachment(runtimeLease)
            && inputs.flatMap(\.plans).allSatisfy {
                $0.tabReceipt.accepts($0.tab)
            }
    }

    func stage() -> StageOutcome {
        guard validateForStaging() else {
            return cancelPrepared() ? .restored : .conflicted
        }
        guard residences.stage() else {
            state = .terminal
            return .restored
        }
        for input in inputs {
            for plan in input.plans {
                plan.tab.isPinned = false
                plan.tab.isSpacePinned = false
                plan.tab.bindToShortcutPin(input.pin)
                plan.tab.spaceId = plan.target.spaceID
                plan.tab.folderId = plan.target.folderID
            }
        }
        state = .staged
        guard stagedModelIsExact() else {
            return rollback() ? .restored : .conflicted
        }
        return .staged
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return stagedModelOwnershipIsExact()
            && runtimeConnection.acceptsExactAttachment(runtimeLease)
    }

    private func stagedModelOwnershipIsExact() -> Bool {
        residences.stagedModelIsExact()
            && inputs.allSatisfy { input in
                input.plans.allSatisfy { plan in
                    plan.tab.shortcutPinId == input.pin.id
                        && plan.tab.shortcutPinRole == input.pin.role
                        && plan.tab.isPinned == false
                        && plan.tab.isSpacePinned == false
                        && plan.tab.isShortcutLiveInstance
                        && plan.tab.spaceId == plan.target.spaceID
                        && plan.tab.folderId == plan.target.folderID
                }
            }
    }

    func publishModel() {
        guard stagedModelIsExact() else {
            preconditionFailure("Shortcut binding target model was not exact")
        }
        state = .published
        precondition(residences.publish())
    }

    func publishTerminalEffects() {
        guard case .published = state else {
            preconditionFailure("Shortcut binding target model was not published")
        }
        state = .terminal
        inputs.flatMap(\.plans).forEach {
            profiles.didCommitShortcutSpaceDeparture($0.tab)
        }
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let cancelled = residences.cancelPrepared()
        state = cancelled ? .terminal : .conflicted
        return cancelled
    }

    func rollback() -> Bool {
        guard stagedModelIsExact(), residences.canRollback() else {
            state = .conflicted
            return false
        }
        inputs.flatMap(\.plans).forEach {
            $0.tabReceipt.restoreBindingModel(to: $0.tab)
        }
        let restored = residences.rollback()
        state = restored ? .terminal : .conflicted
        return restored
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged:
            return stagedModelOwnershipIsExact()
                && residences.canAbandonForTerminalDrain()
        case .published, .terminal: return true
        case .prepared, .conflicted: return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        if case .staged = state { residences.abandonForTerminalDrain() }
        state = .terminal
        return true
    }
}
