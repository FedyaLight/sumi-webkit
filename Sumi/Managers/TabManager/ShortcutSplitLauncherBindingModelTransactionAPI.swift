import SumiWebRuntime

@MainActor
protocol ShortcutSplitLauncherBindingModelTransaction: AnyObject {
    var exactBindingTabs: [Tab] { get }
    func validateForStaging() -> Bool
    func stageCatalog() -> Bool
    func prepareStructuralRollbackAfterCatalogStage() -> Bool
    func stageBinding() throws
    func stagedModelIsExact() -> Bool
    func canClaimTerminalModel() -> Bool
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome
    func claimedModelIsExact() -> Bool
    func publishModelCommit(beforeWindowPublication: () -> Void)
    func publishTerminalEffects()
    func cancelPrepared() -> Bool
    func rollbackBinding() throws
    func confirmStructuralRollback() -> Bool
    func publishRollback()
    func retainsModelAfterFailedStage() -> Bool
    func canSettleTerminalDrain() -> Bool
    func settleTerminalDrain() -> Bool
}

enum ShortcutSplitLauncherAggregateError: Error {
    case stale
    case compensationFailed
}
