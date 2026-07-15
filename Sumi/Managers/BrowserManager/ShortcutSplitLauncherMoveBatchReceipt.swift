@MainActor
struct ShortcutSplitLauncherStagedMove {
    let bindings: ShortcutTabBindingRefreshTransaction
    let destination: ShortcutSplitLauncherDestination
}

/// Concrete ownership of a fully staged launcher catalog/residence batch.
@MainActor
final class ShortcutSplitLauncherMoveBatchReceipt:
    ShortcutSplitLauncherMoveBatchParticipant {
    private enum State {
        case staged
        case modelSettled
        case terminal
    }

    private let checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint
    private let moves: [ShortcutSplitLauncherStagedMove]
    private let folderOpenState: TabFolderOpenStateService
    private var state = State.staged

    init(
        checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint,
        moves: [ShortcutSplitLauncherStagedMove],
        folderOpenState: TabFolderOpenStateService
    ) {
        self.checkpoint = checkpoint
        self.moves = moves
        self.folderOpenState = folderOpenState
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        return checkpoint.isCurrent()
            && moves.allSatisfy { $0.bindings.isCurrent() }
    }

    func canRollback() -> Bool { isCurrent() }

    func rollback() -> Bool {
        guard isCurrent() else { return false }
        if checkpoint.ownsResidenceSnapshot {
            guard checkpoint.restore() else { return false }
            moves.forEach { $0.bindings.discardAfterAggregateRollback() }
        } else {
            for move in moves.reversed() {
                guard move.bindings.rollback() else { return false }
            }
            guard checkpoint.restoreCatalog() else { return false }
        }
        state = .terminal
        return true
    }

    func settleAdmittedModel() {
        guard case .staged = state else {
            preconditionFailure("Launcher move batch was not staged")
        }
        for move in moves {
            move.bindings.settleAdmittedModel()
        }
        state = .modelSettled
    }

    func publishAndExecute() {
        guard case .modelSettled = state else { return }
        state = .terminal
        moves.forEach { $0.bindings.publishAndExecute() }
        let folderIDs = Set(moves.compactMap(\.destination.folderId))
            .sorted { $0.uuidString < $1.uuidString }
        folderIDs.forEach(folderOpenState.openFolderIfNeeded)
    }
}
