@MainActor
final class RegularTabShortcutDurableStructureParticipant {
    private enum State {
        case prepared
        case open(TabStructuralCollectionMutationOwner.PreparedAggregate)
        case staged(TabStructuralCollectionMutationOwner.PreparedAggregate)
        case structuralPublished
        case modelPublished
        case terminal
    }

    private let mutations: TabStructuralCollectionMutationOwner
    private let topology: SplitGroupReplacementReceipt?
    private var presentation: PreparedWindowSplitPresentationSettlement?
    private var state = State.prepared

    init(
        mutations: TabStructuralCollectionMutationOwner,
        topology: SplitGroupReplacementReceipt?
    ) {
        self.mutations = mutations
        self.topology = topology
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return topology?.isCurrent() ?? true
    }

    func admitPresentation(
        _ value: PreparedWindowSplitPresentationSettlement,
        windowStates: [UUID: BrowserWindowShortcutMutationState]
    ) -> Bool {
        guard case .prepared = state, presentation == nil,
              value.admitAggregateWindowStates(windowStates) else {
            return false
        }
        presentation = value
        return true
    }

    func begin() -> Bool {
        guard validateForStaging(),
              let structural = mutations.prepareAggregate() else {
            return false
        }
        guard topology?.commitModel() ?? true else {
            _ = structural.rollback()
            topology?.rollback()
            _ = presentation?.cancelPrepared()
            state = .terminal
            return false
        }
        state = .open(structural)
        return true
    }

    func stagePresentation() -> Bool {
        guard case .open = state else { return false }
        guard let presentation else { return true }
        guard presentation.stage() else {
            _ = presentation.settleAfterFailedStage()
            return false
        }
        return true
    }

    func stage() -> Bool {
        guard case .open(let structural) = state,
              structural.stage(),
              presentation?.acceptAggregateWindowSettlement() ?? true else {
            return false
        }
        state = .staged(structural)
        return isCurrent()
    }

    func isCurrent() -> Bool {
        guard case .staged(let structural) = state else { return false }
        return structural.isCurrent()
            && (topology?.committedModelIsExact() ?? true)
            && (presentation?.aggregateWindowModelIsExact() ?? true)
    }

    func publishStructural() {
        guard case .staged(let structural) = state, isCurrent() else {
            preconditionFailure("Shortcut durable model was not staged")
        }
        precondition(structural.publish())
        presentation?.publishAdmittedModel()
        state = .structuralPublished
    }

    func publishTopology() {
        guard case .structuralPublished = state else {
            preconditionFailure("Shortcut structure was not published")
        }
        topology?.publish()
        state = .modelPublished
    }

    func publishTerminalEffects() {
        guard case .modelPublished = state else {
            preconditionFailure("Shortcut structure model was not published")
        }
        presentation?.publishTerminalEffects()
        state = .terminal
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        topology?.rollback()
        var cancelled = true
        if presentation?.cancelPrepared() == false { cancelled = false }
        state = .terminal
        return cancelled
    }

    func rollback() -> Bool {
        let structural: TabStructuralCollectionMutationOwner.PreparedAggregate
        switch state {
        case .open(let value), .staged(let value): structural = value
        case .prepared, .structuralPublished, .modelPublished, .terminal:
            return false
        }
        let restored = structural.rollback()
        presentation?.rollback()
        let topologyRestored = restoreTopology()
        state = .terminal
        return restored && topologyRestored
    }

    func canAbandonForTerminalDrain() -> Bool {
        guard case .staged(let structural) = state else { return false }
        return structural.canAbandonForTerminalDrain()
            && (topology?.canAbandonForTerminalDrain() ?? true)
            && (presentation?.canAbandonForTerminalDrain() ?? true)
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        guard case .staged(let structural) = state else { return }
        state = .terminal
        structural.abandonForTerminalDrain()
        topology?.abandonForTerminalDrain()
        presentation?.abandonForTerminalDrain()
    }

    func prepareTerminalDrain()
        -> PreparedRegularTabShortcutDurableTerminalDrain? {
        guard case .staged(let structural) = state else { return nil }
        return PreparedRegularTabShortcutDurableTerminalDrain(
            structural: structural,
            topology: topology,
            presentation: presentation
        )
    }

    func finishTerminalDrain(
        _ drain: PreparedRegularTabShortcutDurableTerminalDrain
    ) {
        guard case .staged(let structural) = state,
              drain.matches(
                  structural: structural,
                  topology: topology,
                  presentation: presentation
              ) else {
            preconditionFailure("Detached durable drain became stale")
        }
        state = .terminal
        drain.finish()
    }

    private func restoreTopology() -> Bool {
        guard topology?.rollbackModel() ?? true else { return false }
        topology?.rollback()
        return true
    }
}
