@MainActor
final class ShortcutSplitLauncherMoveBatchReceipt:
    ShortcutSplitLauncherMoveBatchParticipant {
    private enum State { case staged, accepted, terminal }

    private let bindingModel: ShortcutSplitLauncherBindingAggregateTransaction
    private let profiles: ShortcutTabProfileAssignmentBatch
    private let folders: ShortcutSplitLauncherFolderPublicationGate
    private var state = State.staged

    init(
        bindingModel: ShortcutSplitLauncherBindingAggregateTransaction,
        profiles: ShortcutTabProfileAssignmentBatch,
        folders: ShortcutSplitLauncherFolderPublicationGate
    ) {
        self.bindingModel = bindingModel
        self.profiles = profiles
        self.folders = folders
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        return bindingModel.validateForStaging()
            && profiles.isCurrent(for: bindingModel)
    }

    func rollback() -> Bool {
        guard case .staged = state,
              bindingModel.cancelPrepared() else { return false }
        state = .terminal
        return true
    }

    func settleAdmittedModel() -> Bool {
        guard case .staged = state, isCurrent() else { return false }
        let outcome = profiles.execute(bindingModel: bindingModel)
        guard outcome.wasAccepted else {
            state = .terminal
            return false
        }
        state = .accepted
        return true
    }

    func publishAdmittedModel() {
        guard case .accepted = state else {
            preconditionFailure("Launcher binding batch was not accepted")
        }
    }

    func commitTerminalEffects(
        openingFoldersWith folderOpenState: TabFolderOpenStateService
    ) {
        guard case .accepted = state else {
            preconditionFailure("Launcher binding batch was not accepted")
        }
        state = .terminal
        folders.requestCommit(openingFoldersWith: folderOpenState)
    }
}
