import SumiWebRuntime

@testable import Sumi

@MainActor
final class TestWebViewReplacementModelTransaction:
    ShortcutTabBindingAggregateTransaction {
    let exactBindingTabs: [Tab]
    private let validateAction: () -> Bool
    private let stageAction: () throws -> Void
    private let exactAction: () -> Bool
    private let canClaimAction: () -> Bool
    private let claimAction: () -> WebViewReplacementTerminalModelClaimOutcome
    private let claimedExactAction: () -> Bool
    private let publishCommitAction: () -> Void
    private let rollbackAction: () throws -> Void
    private let publishRollbackAction: () -> Void
    private let canSettleTerminalDrainAction: () -> Bool
    private let terminalDrainAction: () -> Void

    init(
        exactBindingTabs: [Tab] = [],
        validate: @escaping () -> Bool = { true },
        stage: @escaping () throws -> Void = {},
        stagedModelIsExact: @escaping () -> Bool = { true },
        canClaimTerminalModel: @escaping () -> Bool = { true },
        claimTerminalModel: @escaping () ->
            WebViewReplacementTerminalModelClaimOutcome = { .sealed },
        claimedModelIsExact: @escaping () -> Bool = { true },
        publishCommit: @escaping () -> Void = {},
        rollback: @escaping () throws -> Void = {},
        publishRollback: @escaping () -> Void = {},
        canSettleTerminalDrain: @escaping () -> Bool = { true },
        settleTerminalDrain: @escaping () -> Void = {}
    ) {
        self.exactBindingTabs = exactBindingTabs
        validateAction = validate
        stageAction = stage
        exactAction = stagedModelIsExact
        canClaimAction = canClaimTerminalModel
        claimAction = claimTerminalModel
        claimedExactAction = claimedModelIsExact
        publishCommitAction = publishCommit
        rollbackAction = rollback
        publishRollbackAction = publishRollback
        canSettleTerminalDrainAction = canSettleTerminalDrain
        terminalDrainAction = settleTerminalDrain
    }

    func validateForStaging() -> Bool { validateAction() }
    func cancelPrepared() -> Bool { validateAction() }
    func stage() throws { try stageAction() }
    func retainsModelAfterFailedStage() -> Bool { false }
    func stagedModelIsExact() -> Bool { exactAction() }
    func canClaimTerminalModel() -> Bool { canClaimAction() }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        claimAction()
    }
    func claimedModelIsExact() -> Bool { claimedExactAction() }
    func publishCommit() { publishCommitAction() }
    func rollback() throws { try rollbackAction() }
    func publishRollback() { publishRollbackAction() }
    func canSettleTerminalDrain() -> Bool {
        canSettleTerminalDrainAction()
    }
    func settleTerminalDrain() -> Bool {
        terminalDrainAction()
        return true
    }
}
