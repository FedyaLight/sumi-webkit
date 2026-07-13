import AppKit
import Foundation

/// Executes only the concrete consequences of typed popup-state retirements.
/// It cannot admit, stage, or commit a popup session.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupRetirementService {
    private let sessions: ExtensionActionPopupSessionLedger
    private let focusRestorer: ExtensionActionPopupFocusRestorer
    private let telemetry: ExtensionActionPopupTelemetry

    init(
        sessions: ExtensionActionPopupSessionLedger,
        focusRestorer: ExtensionActionPopupFocusRestorer,
        telemetry: ExtensionActionPopupTelemetry
    ) {
        self.sessions = sessions
        self.focusRestorer = focusRestorer
        self.telemetry = telemetry
    }

    func execute(_ outcome: ExtensionActionPopupRetirementOutcome?) {
        guard let outcome else { return }
        execute([outcome])
    }

    func execute(_ outcomes: [ExtensionActionPopupRetirementOutcome]) {
        for outcome in outcomes {
            guard let payload = outcome.take() else { continue }
            switch payload {
            case .pending(let pending):
                retirePending(pending)
            case .session(let retirement):
                retireSession(retirement)
            case .closingFinished(let completion):
                completion.session.finishPopoverClosing()
                restoreFocus(
                    completion.session.focusReceipt,
                    revision: completion.focusRevision,
                    enabled: completion.restoresFocus
                )
            }
        }
    }

    func failPending(
        _ claim: ExtensionActionPopupSessionClaim,
        error: Error
    ) {
        execute(sessions.failPending(claim, error: error))
    }

    func popoverDidClose(
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover
    ) {
        execute(sessions.popoverDidClose(claim: claim, popover: popover))
    }

    func popoverWillClose(
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover
    ) {
        execute(sessions.popoverWillClose(claim: claim, popover: popover))
    }

    func closePopup(backedBy profileIDs: Set<UUID>) {
        execute(sessions.closePopup(backedBy: profileIDs))
    }

    func retire(binding receipt: ExtensionContextBindingReceipt) {
        execute(sessions.retire(binding: receipt))
    }

    private func retirePending(
        _ pending: ExtensionActionPopupPendingRetirement
    ) {
        pending.task?.cancel()
        if let retirement = pending.sessionRetirement {
            retireSession(retirement)
        } else {
            restoreFocus(
                pending.inheritedFocusReceipt,
                revision: pending.focusRevision,
                enabled: pending.restoresFocus
            )
        }
        pending.completion.settle(pending.error)
    }

    private func retireSession(
        _ retirement: ExtensionActionPopupSessionRetirement
    ) {
        let session = retirement.session
        session.retirePresentation(
            closePhysicalPopup: retirement.closePhysicalPopup,
            awaitPopoverDidClose: retirement.awaitPopoverDidClose
        )
        if session.telemetryCommitted {
            telemetry.recordClosed(
                extensionID: session.claim.extensionID,
                replacementVisible: retirement.replacementVisible
            )
            telemetry.logClosed(extensionID: session.claim.extensionID)
        }
        guard retirement.awaitPopoverDidClose == false else { return }
        restoreFocus(
            session.focusReceipt,
            revision: retirement.focusRevision,
            enabled: retirement.restoresFocus
        )
    }

    private func restoreFocus(
        _ receipt: ExtensionActionPopupFocusReceipt?,
        revision: UInt64,
        enabled: Bool
    ) {
        guard enabled else { return }
        focusRestorer.restore(receipt) { [weak sessions] in
            sessions?.canRestoreFocus(after: revision) == true
        }
    }
}
