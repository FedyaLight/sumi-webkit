@MainActor
final class ShortcutLiveRetirementBatchPhysicalEffect {
    private let scopedPorts: ShortcutLiveRetirementScopedPortEffect
    private let committedDestroy: ShortcutLiveRetirementCommittedDestroyEffect?
    private var isPublished = false

    init(
        plan: ShortcutLiveRetirementBatchPlan,
        effect: ShortcutLiveRetirementBatchRuntimeParticipant.ClaimedEffect,
        retirement: TabRuntimeRetirementService
    ) {
        let tabClosure: ShortcutLiveRetirementScopedPortEffect
            .TabClosurePublicationIntent
        if case .terminallyDrained = effect {
            tabClosure = .terminalDrainAlreadyPublished
        } else {
            tabClosure = .publishExactTabs
        }
        scopedPorts = ShortcutLiveRetirementScopedPortEffect(
            plan: plan,
            tabClosure: tabClosure
        )
        if case .committed(let value) = effect {
            committedDestroy = ShortcutLiveRetirementCommittedDestroyEffect(
                committed: value, retirement: retirement
            )
        } else {
            committedDestroy = nil
        }
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        scopedPorts.publish()
        committedDestroy?.publish()
    }
}
