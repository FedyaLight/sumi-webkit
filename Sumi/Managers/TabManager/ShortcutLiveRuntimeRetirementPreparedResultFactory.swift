import Foundation

@MainActor
enum ShortcutLiveRuntimeRetirementPreparedResultFactory {
    static func make(
        plan: ShortcutLiveTabRetirementPlan,
        effect: ShortcutLiveRuntimeRetirementEffect,
        terminalEffect: PreparedShortcutLiveTabRetirementTerminalEffect? = nil
    ) -> PreparedShortcutLiveTabRetirement {
        let runtimeTeardown: PreparedTabRuntimeTeardown?
        let committed: CommittedTabRuntimeRetirementCleanupOwnership?
        let drained: Set<UUID>
        switch effect {
        case .none:
            runtimeTeardown = nil; committed = nil; drained = []
        case .empty(let prepared):
            runtimeTeardown = prepared; committed = nil; drained = []
        case .committed(let prepared):
            runtimeTeardown = nil; committed = prepared; drained = []
        case .terminallyDrained(let tabIDs):
            runtimeTeardown = nil; committed = nil; drained = tabIDs
        }
        return PreparedShortcutLiveTabRetirement(
            tabs: plan.tabs,
            runtime: plan.runtimeLease.registry,
            runtimeTeardown: runtimeTeardown,
            committedRuntimeRetirement: committed,
            terminallyDrainedTabIDs: drained,
            runtimeAttachment: TabRuntimeAttachmentWitness(
                connection: plan.runtimeConnection,
                lease: plan.runtimeLease
            ),
            terminalEffect: terminalEffect,
            result: plan.result
        )
    }
}
