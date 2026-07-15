@MainActor
final class DetachedTabShortcutCommitPublication {
    private let terminal: RegularTabShortcutTerminalEffects
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        terminal: RegularTabShortcutTerminalEffects,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.terminal = terminal
        self.structuralLookup = structuralLookup
    }

    func publishModel(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) {
        structuralLookup.withTransaction {
            binding.publishModelCommit {
                runtime.settleTerminalModel()
                durable.publishStructural()
            }
            durable.publishTopology()
            binding.publishTerminalEffects()
            durable.publishTerminalEffects()
            terminal.publish()
        }
    }

    func publishTerminalEffects(
        _ runtime: DetachedTabRuntimeRetirementParticipant
    ) {
        runtime.publishTerminalModelEffects()
        runtime.publishRuntimeEffects()
    }
}
