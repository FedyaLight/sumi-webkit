import AppKit
import WebKit

/// Sole authority for pending, active, and closing popup identities. It
/// returns typed retirement outcomes; physical close, focus, completion, and
/// telemetry effects are executed by `ExtensionActionPopupRetirementService`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSessionLedger {
    private struct Pending {
        let claim: ExtensionActionPopupSessionClaim
        let evidence: ExtensionActionPopupCallbackEvidence
        let completion: ExtensionActionPopupCompletion
        var task: Task<Void, Never>?
        var session: ExtensionActionPopupSession?
        let inheritedFocusReceipt: ExtensionActionPopupFocusReceipt?
        let focusRevision: UInt64
    }

    private struct Closing {
        let session: ExtensionActionPopupSession
        let focusRevision: UInt64
        let restoresFocus: Bool
    }

    private enum PendingRetirementReason {
        case superseded
        case failed
        case quiesced
        case naturalClose

        var restoresFocus: Bool { self != .superseded }
    }

    private var nextRevision: UInt64 = 1
    private var latestReservedRevision: UInt64 = 0
    private var focusSupersessionRevision: UInt64 = 0
    private var pending: Pending?
    private var active: ExtensionActionPopupSession?
    private var closingByPopoverID: [ObjectIdentifier: Closing] = [:]

    var hasVisibleSession: Bool { active != nil }

    func admits(popover: NSPopover, popupWebView: WKWebView) -> Bool {
        admits(
            popoverID: ObjectIdentifier(popover),
            popupWebViewID: ObjectIdentifier(popupWebView)
        )
    }

    func focusTransferCandidate() -> ExtensionActionPopupFocusReceipt? {
        pending?.session?.focusReceipt
            ?? pending?.inheritedFocusReceipt
            ?? active?.focusReceipt
    }

    func canRestoreFocus(after revision: UInt64) -> Bool {
        active == nil && focusSupersessionRevision == revision
    }

    func reserve(
        evidence: ExtensionActionPopupCallbackEvidence,
        action: WKWebExtension.Action,
        popover: NSPopover,
        popupWebView: WKWebView
    ) -> ExtensionActionPopupSessionClaim {
        precondition(
            nextRevision < UInt64.max,
            "Action popup session revision exhausted"
        )
        let claim = ExtensionActionPopupSessionClaim(
            revision: nextRevision,
            extensionID: evidence.extensionID,
            profileID: evidence.profileID,
            actionID: ObjectIdentifier(action),
            popoverID: ObjectIdentifier(popover),
            popupWebViewID: ObjectIdentifier(popupWebView)
        )
        nextRevision += 1
        latestReservedRevision = claim.revision
        return claim
    }

    func activate(
        _ claim: ExtensionActionPopupSessionClaim,
        evidence: ExtensionActionPopupCallbackEvidence,
        completion: ExtensionActionPopupCompletion
    ) -> ExtensionActionPopupActivation? {
        guard claim.revision == latestReservedRevision,
              claim.extensionID == evidence.extensionID,
              claim.profileID == evidence.profileID,
              admits(
                  popoverID: claim.popoverID,
                  popupWebViewID: claim.popupWebViewID
              )
        else { return nil }
        focusSupersessionRevision &+= 1
        let superseded = pending
        pending = Pending(
            claim: claim,
            evidence: evidence,
            completion: completion,
            task: nil,
            session: nil,
            inheritedFocusReceipt: superseded?.session?.focusReceipt
                ?? superseded?.inheritedFocusReceipt,
            focusRevision: focusSupersessionRevision
        )
        return ExtensionActionPopupActivation(
            superseded: superseded.map {
                pendingRetirement(
                    $0,
                    error: CancellationError(),
                    reason: .superseded
                )
            }
        )
    }

    func isLatestReservation(
        _ claim: ExtensionActionPopupSessionClaim
    ) -> Bool {
        claim.revision == latestReservedRevision
    }

    func attach(
        _ task: Task<Void, Never>,
        to claim: ExtensionActionPopupSessionClaim
    ) -> Bool {
        guard pending?.claim == claim else { return false }
        pending?.task = task
        return true
    }

    func isPending(_ claim: ExtensionActionPopupSessionClaim) -> Bool {
        pending?.claim == claim
    }

    func isActive(_ session: ExtensionActionPopupSession) -> Bool {
        active === session
    }

    func stage(
        _ session: ExtensionActionPopupSession,
        for claim: ExtensionActionPopupSessionClaim
    ) -> Bool {
        guard pending?.claim == claim,
              pending?.session == nil,
              session.claim == claim
        else { return false }
        session.bindFocusRevision(pending?.focusRevision ?? 0)
        pending?.session = session
        return true
    }

    func commit(
        _ session: ExtensionActionPopupSession
    ) -> ExtensionActionPopupCommit? {
        guard pending?.claim == session.claim,
              pending?.completion === session.completion,
              pending?.session === session
        else { return nil }
        let previous = active
        guard previous?.popover !== session.popover,
              previous?.popupWebView !== session.popupWebView
        else { return nil }
        pending = nil
        active = session
        return ExtensionActionPopupCommit(
            phase: previous == nil ? .opened : .reopened,
            replaced: previous.map {
                .session(sessionRetirement(
                    $0,
                    closePhysicalPopup: $0.popover.isShown,
                    awaitPopoverDidClose: $0.popover.isShown,
                    restoresFocus: false,
                    replacementVisible: true
                ))
            }
        )
    }

    func settleCommitted(_ session: ExtensionActionPopupSession) -> Bool {
        active === session
    }

    func failPending(
        _ claim: ExtensionActionPopupSessionClaim,
        error: Error
    ) -> ExtensionActionPopupRetirementOutcome? {
        guard let pending, pending.claim == claim else { return nil }
        self.pending = nil
        return pendingRetirement(
            pending,
            error: error,
            reason: .failed
        )
    }

    func popoverDidClose(
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover
    ) -> [ExtensionActionPopupRetirementOutcome] {
        if let pending, pending.claim == claim,
           pending.claim.popoverID == ObjectIdentifier(popover) {
            self.pending = nil
            return [pendingRetirement(
                pending,
                error: CancellationError(),
                reason: .naturalClose
            )]
        }
        let popoverID = ObjectIdentifier(popover)
        if let closing = closingByPopoverID[popoverID],
           closing.session.claim == claim,
           closing.session.popover === popover {
            closingByPopoverID.removeValue(forKey: popoverID)
            return [.closingFinished(.init(
                session: closing.session,
                focusRevision: closing.focusRevision,
                restoresFocus: closing.restoresFocus
            ))]
        }
        guard let active,
              active.claim == claim,
              active.popover === popover
        else { return [] }
        self.active = nil
        return [.session(sessionRetirement(
            active,
            closePhysicalPopup: false,
            awaitPopoverDidClose: false,
            restoresFocus: true,
            replacementVisible: false
        ))]
    }

    func popoverWillClose(
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover
    ) -> [ExtensionActionPopupRetirementOutcome] {
        var outcomes: [ExtensionActionPopupRetirementOutcome] = []
        let popoverID = ObjectIdentifier(popover)
        if let pending, pending.claim == claim,
           pending.claim.popoverID == popoverID {
            self.pending = nil
            outcomes.append(pendingRetirement(
                pending,
                error: CancellationError(),
                reason: .naturalClose,
                alreadyClosing: true
            ))
        }
        if let active, active.claim == claim, active.popover === popover {
            self.active = nil
            outcomes.append(.session(sessionRetirement(
                active,
                closePhysicalPopup: false,
                awaitPopoverDidClose: true,
                restoresFocus: true,
                replacementVisible: false
            )))
        }
        return outcomes
    }

    func closePopup(
        backedBy profileIDs: Set<UUID>
    ) -> [ExtensionActionPopupRetirementOutcome] {
        var outcomes: [ExtensionActionPopupRetirementOutcome] = []
        if let pending, profileIDs.contains(pending.claim.profileID) {
            self.pending = nil
            outcomes.append(pendingRetirement(
                pending,
                error: CancellationError(),
                reason: .quiesced
            ))
        }
        if let active, profileIDs.contains(active.claim.profileID) {
            self.active = nil
            outcomes.append(.session(sessionRetirement(
                active,
                closePhysicalPopup: active.popover.isShown,
                awaitPopoverDidClose: active.popover.isShown,
                restoresFocus: true,
                replacementVisible: false
            )))
        }
        return outcomes
    }

    func retire(
        binding receipt: ExtensionContextBindingReceipt
    ) -> [ExtensionActionPopupRetirementOutcome] {
        var outcomes: [ExtensionActionPopupRetirementOutcome] = []
        if let pending, pending.evidence.matches(receipt) {
            self.pending = nil
            outcomes.append(pendingRetirement(
                pending,
                error: CancellationError(),
                reason: .quiesced
            ))
        }
        if let active, active.evidence.matches(receipt) {
            self.active = nil
            outcomes.append(.session(sessionRetirement(
                active,
                closePhysicalPopup: active.popover.isShown,
                awaitPopoverDidClose: active.popover.isShown,
                restoresFocus: true,
                replacementVisible: false
            )))
        }
        return outcomes
    }

    private func admits(
        popoverID: ObjectIdentifier,
        popupWebViewID: ObjectIdentifier
    ) -> Bool {
        guard active?.claim.popoverID != popoverID,
              pending?.claim.popoverID != popoverID,
              closingByPopoverID[popoverID] == nil,
              active?.claim.popupWebViewID != popupWebViewID,
              pending?.claim.popupWebViewID != popupWebViewID,
              closingByPopoverID.values.contains(where: {
                  $0.session.claim.popupWebViewID == popupWebViewID
              }) == false
        else { return false }
        return true
    }

    private func pendingRetirement(
        _ pending: Pending,
        error: Error,
        reason: PendingRetirementReason,
        alreadyClosing: Bool = false
    ) -> ExtensionActionPopupRetirementOutcome {
        let session = pending.session.map {
            sessionRetirement(
                $0,
                closePhysicalPopup: alreadyClosing == false && $0.popover.isShown,
                awaitPopoverDidClose: $0.popover.isShown,
                restoresFocus: reason.restoresFocus,
                replacementVisible: false
            )
        }
        return .pending(.init(
            task: pending.task,
            sessionRetirement: session,
            inheritedFocusReceipt: pending.inheritedFocusReceipt,
            focusRevision: pending.focusRevision,
            completion: pending.completion,
            error: error,
            restoresFocus: reason.restoresFocus
        ))
    }

    private func sessionRetirement(
        _ session: ExtensionActionPopupSession,
        closePhysicalPopup: Bool,
        awaitPopoverDidClose: Bool,
        restoresFocus: Bool,
        replacementVisible: Bool
    ) -> ExtensionActionPopupSessionRetirement {
        if awaitPopoverDidClose {
            closingByPopoverID[session.claim.popoverID] = Closing(
                session: session,
                focusRevision: session.focusRevision,
                restoresFocus: restoresFocus
            )
        }
        return ExtensionActionPopupSessionRetirement(
            session: session,
            closePhysicalPopup: closePhysicalPopup,
            awaitPopoverDidClose: awaitPopoverDidClose,
            focusRevision: session.focusRevision,
            restoresFocus: restoresFocus,
            replacementVisible: replacementVisible
        )
    }

}
