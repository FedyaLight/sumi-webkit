import Foundation

@MainActor
final class ShortcutSplitLauncherFolderPublicationGate {
    private enum ModelOutcome { case pending, committed, rolledBack }

    private let folderIDs: [UUID]
    private var modelOutcome = ModelOutcome.pending
    private var folderOpenState: TabFolderOpenStateService?
    private var didPublish = false

    init(folderIDs: Set<UUID>) {
        self.folderIDs = folderIDs.sorted { $0.uuidString < $1.uuidString }
    }

    func requestCommit(
        openingFoldersWith folderOpenState: TabFolderOpenStateService
    ) {
        guard self.folderOpenState == nil else {
            preconditionFailure("Launcher folder publication was requested twice")
        }
        self.folderOpenState = folderOpenState
        publishIfReady()
    }

    func bindingDidCommit() {
        guard case .pending = modelOutcome else {
            preconditionFailure("Launcher binding settled more than once")
        }
        modelOutcome = .committed
        publishIfReady()
    }

    func bindingDidRollback() {
        guard case .pending = modelOutcome else { return }
        modelOutcome = .rolledBack
    }

    private func publishIfReady() {
        guard case .committed = modelOutcome,
              let folderOpenState,
              didPublish == false else { return }
        didPublish = true
        folderIDs.forEach(folderOpenState.openFolderIfNeeded)
    }
}
