import Foundation
import SumiWebRuntime

@MainActor
final class ProfileReferenceAdmittedModelTransaction:
    WebViewReplacementModelTransaction {
    private enum AdmissionError: Error {
        case stale
    }

    private let model: any WebViewReplacementModelTransaction
    private let admissions: ProfileReferenceAdmissionLedger
    private let receipt: ProfileReferenceAdmissionReceipt

    init(
        model: any WebViewReplacementModelTransaction,
        admissions: ProfileReferenceAdmissionLedger,
        receipt: ProfileReferenceAdmissionReceipt
    ) {
        self.model = model
        self.admissions = admissions
        self.receipt = receipt
    }

    func validateForStaging() -> Bool {
        admissions.validate(receipt) && model.validateForStaging()
    }

    func stage() throws {
        guard admissions.validate(receipt) else { throw AdmissionError.stale }
        try model.stage()
    }

    func retainsModelAfterFailedStage() -> Bool {
        model.retainsModelAfterFailedStage()
    }

    func stagedModelIsExact() -> Bool {
        model.stagedModelIsExact()
    }

    func canClaimTerminalModel() -> Bool {
        admissions.validate(receipt) && model.canClaimTerminalModel()
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard admissions.validate(receipt) else { return .terminallyDrained }
        return model.claimTerminalModel()
    }

    func claimedModelIsExact() -> Bool {
        admissions.validate(receipt) && model.claimedModelIsExact()
    }

    func publishCommit() {
        model.publishCommit()
    }

    func rollback() throws {
        try model.rollback()
    }

    func publishRollback() {
        model.publishRollback()
    }

    func canSettleTerminalDrain() -> Bool {
        model.canSettleTerminalDrain()
    }

    func settleTerminalDrain() -> Bool {
        model.settleTerminalDrain()
    }
}
