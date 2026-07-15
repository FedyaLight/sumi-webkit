import SumiWebRuntime

@MainActor
final class TestWebViewReplacementModelTransaction:
    WebViewReplacementModelTransaction {
    private let validateAction: () -> Bool
    private let stageAction: () throws -> Void
    private let exactAction: () -> Bool
    private let canClaimAction: () -> Bool
    private let claimAction: () -> WebViewReplacementTerminalModelClaimOutcome
    private let publishCommitAction: () -> Void
    private let rollbackAction: () throws -> Void
    private let publishRollbackAction: () -> Void
    private let terminalDrainAction: () -> Void

    init(
        validate: @escaping () -> Bool = { true },
        stage: @escaping () throws -> Void = {},
        stagedModelIsExact: @escaping () -> Bool = { true },
        canClaimTerminalModel: @escaping () -> Bool = { true },
        claimTerminalModel: @escaping () ->
            WebViewReplacementTerminalModelClaimOutcome = { .sealed },
        publishCommit: @escaping () -> Void = {},
        rollback: @escaping () throws -> Void = {},
        publishRollback: @escaping () -> Void = {},
        settleTerminalDrain: @escaping () -> Void = {}
    ) {
        validateAction = validate
        stageAction = stage
        exactAction = stagedModelIsExact
        canClaimAction = canClaimTerminalModel
        claimAction = claimTerminalModel
        publishCommitAction = publishCommit
        rollbackAction = rollback
        publishRollbackAction = publishRollback
        terminalDrainAction = settleTerminalDrain
    }

    func validateForStaging() -> Bool { validateAction() }
    func stage() throws { try stageAction() }
    func stagedModelIsExact() -> Bool { exactAction() }
    func canClaimTerminalModel() -> Bool { canClaimAction() }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        claimAction()
    }
    func publishCommit() { publishCommitAction() }
    func rollback() throws { try rollbackAction() }
    func publishRollback() { publishRollbackAction() }
    func settleTerminalDrain() { terminalDrainAction() }
}
