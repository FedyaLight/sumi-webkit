import Foundation
import SumiWebRuntime

@MainActor
private enum ProfileTransitionModelError: Error {
    case stale
}

/// Exact model transaction for one Tab profile-assignment intent.
@MainActor
final class TabProfileAssignmentModelTransaction:
    WebViewReplacementModelTransaction {
    private let tab: Tab
    private let targetProfileID: UUID
    private let intent: DeferredWebViewProfileAssignmentIntent

    init(
        tab: Tab,
        targetProfileID: UUID,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        self.tab = tab
        self.targetProfileID = targetProfileID
        self.intent = intent
    }

    func validateForStaging() -> Bool {
        intent.resolvedProfileID == targetProfileID
            && tab.profileAssignment.isCurrent(intent)
    }

    func stage() throws {
        guard tab.profileAssignment.stage(intent) else {
            throw ProfileTransitionModelError.stale
        }
    }

    func stagedModelIsExact() -> Bool {
        tab.profileAssignment.isCurrentStaged(intent)
    }

    func canClaimTerminalModel() -> Bool {
        tab.profileAssignment.isCurrentStaged(intent)
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        tab.profileAssignment.finish(intent) ? .sealed : .terminallyDrained
    }

    func publishCommit() {}

    func rollback() throws {
        guard tab.profileAssignment.rollback(intent) else {
            throw ProfileTransitionModelError.stale
        }
    }

    func publishRollback() {}

    func settleTerminalDrain() {
        _ = tab.profileAssignment.settleTerminalDrain(intent)
    }
}

/// Couples profile model staging to the rebuild-epoch authority for the exact
/// Tab set whose WebView generation is being replaced.
@MainActor
final class ProfileTransitionModelParticipant:
    WebViewReplacementModelTransaction {
    private let model: any WebViewReplacementModelTransaction
    private let tabs: [Tab]

    init(
        model: any WebViewReplacementModelTransaction,
        tabs: [Tab]
    ) {
        self.model = model
        self.tabs = tabs
    }

    func validateForStaging() -> Bool { model.validateForStaging() }

    func stage() throws {
        try model.stage()
        tabs.forEach { _ = $0.webViewRebuildEpoch.advance() }
    }

    func stagedModelIsExact() -> Bool { model.stagedModelIsExact() }

    func canClaimTerminalModel() -> Bool {
        model.canClaimTerminalModel()
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        model.claimTerminalModel()
    }

    func publishCommit() { model.publishCommit() }
    func rollback() throws { try model.rollback() }
    func publishRollback() { model.publishRollback() }
    func settleTerminalDrain() { model.settleTerminalDrain() }
}
