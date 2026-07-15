import SumiWebRuntime

@MainActor
final class ShortcutSplitLauncherBindingModelParticipant:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum State {
        case prepared
        case catalogStaged
        case bindingStaged
        case claimed
        case modelPublished
        case awaitingStructuralRollback
        case rolledBack
        case conflicted
        case terminal
    }

    let exactBindingTabs: [Tab]

    private let core: ShortcutTabBindingModelTransaction
    private let checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint
    private let folders: ShortcutSplitLauncherFolderPublicationGate
    private var state = State.prepared

    init(
        core: ShortcutTabBindingModelTransaction,
        checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint,
        folders: ShortcutSplitLauncherFolderPublicationGate
    ) {
        self.core = core
        self.checkpoint = checkpoint
        self.folders = folders
        exactBindingTabs = core.exactBindingTabs
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return checkpoint.validateForStaging() && core.validateForStaging()
    }

    func stageCatalog() -> Bool {
        guard validateForStaging() else { return false }
        switch checkpoint.stage() {
        case .staged:
            state = .catalogStaged
            return true
        case .requiresStructuralRollback:
            state = core.cancelPrepared()
                ? .awaitingStructuralRollback
                : .conflicted
            return false
        }
    }

    func stageBinding() throws {
        guard case .catalogStaged = state else {
            throw ShortcutSplitLauncherAggregateError.stale
        }
        do {
            try core.stage()
            state = .bindingStaged
        } catch {
            state = core.retainsModelAfterFailedStage()
                ? .conflicted
                : .awaitingStructuralRollback
            throw error
        }
    }

    func prepareStructuralRollbackAfterCatalogStage() -> Bool {
        guard case .catalogStaged = state else { return false }
        guard core.cancelPrepared() else {
            state = .conflicted
            return false
        }
        state = .awaitingStructuralRollback
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .bindingStaged = state else { return false }
        return checkpoint.isCurrent() && core.stagedModelIsExact()
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel(),
              core.claimTerminalModel() == .sealed else {
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return checkpoint.isCurrent() && core.claimedModelIsExact()
    }

    func publishModelCommit(
        beforeWindowPublication: () -> Void
    ) {
        guard case .claimed = state else {
            preconditionFailure("Launcher binding model was not claimed")
        }
        state = .modelPublished
        core.publishModelCommit {
            checkpoint.requireCurrentForPublication()
            beforeWindowPublication()
        }
    }

    func publishTerminalEffects() {
        guard case .modelPublished = state else {
            preconditionFailure("Launcher model publication was not completed")
        }
        state = .terminal
        core.publishTerminalEffects()
        folders.bindingDidCommit()
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let coreCancelled = core.cancelPrepared()
        let checkpointCancelled = checkpoint.cancelPrepared()
        guard coreCancelled, checkpointCancelled else {
            state = .conflicted
            return false
        }
        folders.bindingDidRollback()
        state = .terminal
        return true
    }

    func rollbackBinding() throws {
        guard case .bindingStaged = state else {
            throw ShortcutSplitLauncherAggregateError.stale
        }
        try core.rollback()
        state = .awaitingStructuralRollback
    }

    func confirmStructuralRollback() -> Bool {
        guard case .awaitingStructuralRollback = state,
              checkpoint.confirmStructuralRollback() else { return false }
        folders.bindingDidRollback()
        state = .rolledBack
        return true
    }

    func publishRollback() {
        guard case .rolledBack = state else { return }
        core.publishRollback()
        state = .terminal
    }

    func retainsModelAfterFailedStage() -> Bool {
        if case .conflicted = state { return true }
        return false
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .bindingStaged, .claimed, .modelPublished, .conflicted:
            return checkpoint.isCurrent()
                && core.canSettleTerminalDrain()
        case .rolledBack, .terminal:
            return true
        case .prepared, .catalogStaged, .awaitingStructuralRollback:
            return false
        }
    }

    func settleTerminalDrain() -> Bool {
        if case .terminal = state { return true }
        if case .rolledBack = state {
            state = .terminal
            return true
        }
        guard canSettleTerminalDrain() else { return false }
        precondition(core.settleTerminalDrain())
        checkpoint.abandonForTerminalDrain()
        state = .terminal
        return true
    }
}
