import Foundation

typealias ShortcutLiveTerminalDrainEffect = @MainActor () -> Void

enum ShortcutLiveRuntimeRetirementStage {
    case none
    case empty(PreparedTabRuntimeTeardown)
    case leased(TabRuntimeRetirementBatch)
    case repositoryDrained(Set<UUID>)
}

enum ShortcutLiveRuntimeRetirementEffect {
    case none
    case empty(PreparedTabRuntimeTeardown)
    case committed(CommittedTabRuntimeRetirementCleanupOwnership)
    case terminallyDrained(Set<UUID>)
}

@MainActor
enum ShortcutLiveRuntimeRetirementDrain {
    case retirement(ShortcutLiveRuntimeRetirementPublication)
    case cleanup(ShortcutLiveTerminalDrainEffect)

    func finish() -> ShortcutLiveTerminalDrainEffect {
        switch self {
        case .retirement(let publication):
            return publication.finishTerminalDrain()
        case .cleanup(let effect):
            return effect
        }
    }
}

enum ShortcutLiveRuntimeRetirementClaimOutcome {
    case claimed(ShortcutLiveRuntimeRetirementEffect)
    case committedCleanup(CommittedTabRuntimeRetirementCleanupOwnership)
    case conflictCleanup(CommittedTabRuntimeRetirementCleanupOwnership)
    case restored
    case conflict
}

enum ShortcutLiveRuntimeRetirementSettlementOutcome {
    case claimed(
        ShortcutLiveRuntimeRetirementEffect,
        ShortcutLiveRuntimeRetirementPublication
    )
    case cleanup(ShortcutLiveRuntimeRetirementDrain)
    case restored
    case conflict
}
