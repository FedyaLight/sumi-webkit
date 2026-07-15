import Foundation

@MainActor
protocol ShortcutSplitLauncherMoveBatchParticipant: AnyObject {
    func isCurrent() -> Bool
    func rollback() -> Bool
    func settleAdmittedModel() -> Bool
    func publishAdmittedModel()
    func commitTerminalEffects(
        openingFoldersWith folderOpenState: TabFolderOpenStateService
    )
}
