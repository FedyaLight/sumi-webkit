@MainActor
enum ShortcutSplitLauncherMoveTerminalDrain {
    static func settleSiblings(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate
    ) -> Bool {
        guard binding.canSettleTerminalDrain(),
              structural.canAbandonForTerminalDrain(),
              binding.settleTerminalDrain() else { return false }
        structural.abandonForTerminalDrain()
        return true
    }
}
