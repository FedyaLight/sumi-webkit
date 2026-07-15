import SumiWebRuntime

enum DetachedTabRuntimeRetirementParticipantState {
    case prepared
    case beginModelConflict(TabRuntimeRetirementBatch)
    case staged(DetachedTabRuntimeRetirementStage)
    case awaitingStructuralRollback(DetachedTabRuntimeStructuralRollback)
    case cleanupRetained(DetachedTabRuntimeRetainedCleanup)
    case claiming
    case claimed
    case modelSettled
    case runtimePending
    case conflicted
    case terminal

    var retainsCleanup: Bool {
        if case .cleanupRetained = self { return true }
        return false
    }
}

enum DetachedTabRuntimeRetirementStagingOutcome {
    case staged
    case requiresModelConflictCompensation
    case rejected
}

enum DetachedTabRuntimeRetirementDrainOutcome {
    case alreadySettled
    case ready(@MainActor () -> Void)
    case rejected
    case conflicted
}

enum DetachedTabRuntimeStructuralRollback {
    case repositoryRestored
    case modelConflict(TabRuntimeRetirementBatch)
}

enum DetachedTabRuntimeRetainedCleanup {
    case claimed(CommittedTabRuntimeRetirementCleanupOwnership)
    case alreadyDrained
}

enum DetachedTabRuntimeRetirementStage {
    case none
    case empty(RuntimePortRegistry)
    case leased(TabRuntimeRetirementBatch)

    @MainActor
    func isExact(
        tab: Tab,
        retirement: TabRuntimeRetirementService
    ) -> Bool {
        switch self {
        case .none:
            return true
        case .empty(let runtime):
            return tab.webViewSession.allKnownWebViews.isEmpty
                && runtime.webViewLifecycle.canRetireTabWebViews([tab])
        case .leased(let batch):
            return retirement.canCommit(batch)
        }
    }

    @MainActor
    func claim(
        using retirement: TabRuntimeRetirementService
    ) -> DetachedTabRuntimeRetirementClaimOutcome {
        switch self {
        case .none:
            return .claimed(.none)
        case .empty(let runtime):
            return .claimed(.empty(runtime))
        case .leased(let batch):
            switch retirement.commit(batch) {
            case .committed(let committed):
                return .claimed(.committed(committed))
            case .cleanupOnly(let cleanup):
                return .requiresTerminalDrain(.cleanupOnly(cleanup))
            case .noLongerActive:
                return .claimed(.terminallyDrained)
            case .conflict:
                return .commitConflict(batch)
            }
        }
    }
}

enum DetachedTabRuntimeRetirementClaimOutcome {
    case claimed(DetachedTabRuntimeRetirementEffect)
    case requiresTerminalDrain(DetachedTabRuntimeRetirementEffect)
    case commitConflict(TabRuntimeRetirementBatch)
}

enum DetachedTabRuntimeRetirementEffect {
    case none
    case empty(RuntimePortRegistry)
    case committed(CommittedTabRuntimeRetirementCleanupOwnership)
    case cleanupOnly(CommittedTabRuntimeRetirementCleanupOwnership)
    case terminallyDrained

    @MainActor
    func isExact(
        exposure: DetachedTabRuntimeExposureWitness,
        retirement: TabRuntimeRetirementService
    ) -> Bool {
        switch self {
        case .none:
            return exposure.isCurrent()
                && exposure.runtime == nil
                && exposure.tab.webViewSession.allKnownWebViews.isEmpty
        case .empty(let runtime):
            return exposure.isCurrent()
                && exposure.tab.webViewSession.allKnownWebViews.isEmpty
                && runtime.webViewLifecycle
                    .canRetireTabWebViews([exposure.tab])
        case .committed(let committed):
            return exposure.isCurrent()
                && committed.tabs.count == 1
                && committed.tabs.first === exposure.tab
                && retirement.committedRetirementIsExact(committed)
        case .cleanupOnly(let cleanup):
            return cleanup.tabs.count == 1
                && cleanup.tabs.first === exposure.tab
                && cleanup.generations.map(\.tabID) == [exposure.tab.id]
                && exposure.tab.webViewSession.allKnownWebViews.isEmpty
        case .terminallyDrained:
            return exposure.tab.webViewSession.allKnownWebViews.isEmpty
        }
    }
}
