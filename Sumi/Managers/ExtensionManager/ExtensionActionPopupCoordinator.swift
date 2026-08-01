import AppKit
import WebKit

/// Executes one WebKit popup callback transaction. It captures all mutable
/// authority before yielding and delegates visible-session state to the
/// monotonic session ledger.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupCoordinator {
    private let admission: ExtensionActionPopupCallbackAdmission
    private let targetCapture: ExtensionActionPopupTargetCapture
    private let sourceAdmission: ExtensionActionPopupSourceAdmission
    private let sessions: ExtensionActionPopupSessionLedger
    private let retirement: ExtensionActionPopupRetirementService
    private let focusRestorer: ExtensionActionPopupFocusRestorer
    private let commitRecorder: ExtensionActionPopupCommitRecorder
    private let anchorResolver: ExtensionActionPopupAnchorResolver
    private let telemetry: ExtensionActionPopupTelemetry
    private let mutationIsBlocked: @MainActor (UUID) -> Bool
    private let waitForMutation: @MainActor (UUID) async -> Bool

    init(
        admission: ExtensionActionPopupCallbackAdmission,
        targetCapture: ExtensionActionPopupTargetCapture,
        sourceAdmission: ExtensionActionPopupSourceAdmission,
        sessions: ExtensionActionPopupSessionLedger,
        retirement: ExtensionActionPopupRetirementService,
        focusRestorer: ExtensionActionPopupFocusRestorer,
        commitRecorder: ExtensionActionPopupCommitRecorder,
        anchorResolver: ExtensionActionPopupAnchorResolver,
        telemetry: ExtensionActionPopupTelemetry,
        mutationIsBlocked: @escaping @MainActor (UUID) -> Bool,
        waitForMutation: @escaping @MainActor (UUID) async -> Bool
    ) {
        self.admission = admission
        self.targetCapture = targetCapture
        self.sourceAdmission = sourceAdmission
        self.sessions = sessions
        self.retirement = retirement
        self.focusRestorer = focusRestorer
        self.commitRecorder = commitRecorder
        self.anchorResolver = anchorResolver
        self.telemetry = telemetry
        self.mutationIsBlocked = mutationIsBlocked
        self.waitForMutation = waitForMutation
    }

    func present(
        action: WKWebExtension.Action,
        evidence: ExtensionActionPopupCallbackEvidence,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let completion = ExtensionActionPopupCompletion(completionHandler)
        guard admission.isCurrent(evidence) else {
            completion.settle(CancellationError())
            return
        }
        guard let popover = action.popupPopover,
              let popupWebView = action.popupWebView
        else {
            completion.settle(
                ExtensionManagerCallbackError.noPopupPopover.nsError()
            )
            return
        }
        guard sessions.admits(
                  popover: popover,
                  popupWebView: popupWebView
              ),
              let contextConfiguration = evidence.context.webViewConfiguration,
              action.webExtensionContext === evidence.context,
              popupWebView.configuration.webExtensionController
                  === evidence.controller,
              popupWebView.configuration.websiteDataStore
                  === contextConfiguration.websiteDataStore
        else {
            completion.settle(CancellationError())
            return
        }
        let claim = sessions.reserve(
            evidence: evidence,
            action: action,
            popover: popover,
            popupWebView: popupWebView
        )
        guard let target = targetCapture.capture(
                  action: action,
                  evidence: evidence
              ),
              targetCapture.isCurrent(target),
              sessions.isLatestReservation(claim),
              admission.isCurrent(evidence)
        else {
            completion.settle(
                ExtensionManagerCallbackError.actionPopupAnchorUnavailable(
                    anchorSource: nil
                ).nsError()
            )
            return
        }
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            popupWebView.isInspectable = true
            guard targetCapture.isCurrent(target),
                  sessions.isLatestReservation(claim),
                  admission.isCurrent(evidence)
            else {
                completion.settle(CancellationError())
                return
            }
        }
        let sourceReceipt = sourceAdmission.capture(
            evidence: evidence,
            target: target,
            popupWebView: popupWebView
        )
        if target.source.exactTab != nil,
           sourceReceipt == nil {
            completion.settle(CancellationError())
            return
        }
        guard sessions.isLatestReservation(claim),
              targetCapture.isCurrent(target),
              admission.isCurrent(evidence)
        else {
            completion.settle(CancellationError())
            return
        }
        let telemetrySnapshot = telemetry.prepare(
            evidence: evidence,
            source: sourceReceipt
        )
        guard sessions.isLatestReservation(claim),
              targetCapture.isCurrent(target),
              admission.isCurrent(evidence),
              let activation = sessions.activate(
                claim,
                evidence: evidence,
                completion: completion
              )
        else {
            completion.settle(CancellationError())
            return
        }
        retirement.execute(activation.superseded)

        let admission = admission
        let sessions = sessions
        let retirement = retirement
        let focusRestorer = focusRestorer
        let commitRecorder = commitRecorder
        let targetCapture = targetCapture
        let anchorResolver = anchorResolver
        let mutationIsBlocked = mutationIsBlocked
        let waitForMutation = waitForMutation
        let task = Task { @MainActor [
            weak sessions,
            weak retirement,
            weak focusRestorer,
            weak commitRecorder,
            action,
            popover,
            popupWebView
        ] in
            guard let sessions,
                  let retirement,
                  let focusRestorer,
                  let commitRecorder
            else {
                completion.settle(CancellationError())
                return
            }
            if mutationIsBlocked(evidence.profileID) {
                guard await waitForMutation(evidence.profileID) else {
                    retirement.failPending(
                        claim,
                        error: CancellationError()
                    )
                    return
                }
                guard sessions.isPending(claim),
                      admission.isCurrent(evidence),
                      targetCapture.isCurrent(target)
                else {
                    retirement.failPending(
                        claim,
                        error: CancellationError()
                    )
                    return
                }
            }
            await Task.yield()
            guard sessions.isPending(claim),
                  admission.isCurrent(evidence),
                  targetCapture.isCurrent(target),
                  mutationIsBlocked(evidence.profileID) == false,
                  action.webExtensionContext === evidence.context,
                  popupWebView.configuration.webExtensionController
                      === evidence.controller,
                  popupWebView.configuration.websiteDataStore
                      === contextConfiguration.websiteDataStore,
                  claim.actionID == ObjectIdentifier(action),
                  claim.popoverID == ObjectIdentifier(popover),
                  claim.popupWebViewID == ObjectIdentifier(popupWebView)
            else {
                retirement.failPending(claim, error: CancellationError())
                return
            }

            let focusReceipt = focusRestorer.capture(source: sourceReceipt)
                ?? focusRestorer.transfer(
                    sessions.focusTransferCandidate(),
                    to: sourceReceipt
                )
            guard sessions.isPending(claim),
                  admission.isCurrent(evidence),
                  targetCapture.isCurrent(target),
                  mutationIsBlocked(evidence.profileID) == false
            else {
                retirement.failPending(claim, error: CancellationError())
                return
            }
            let sidebarTransientSessionCoordinator = target.source.windowState
                .sidebarTransientSessionCoordinator
            let sidebarTransientPresentationSource =
                sidebarTransientSessionCoordinator.preparedPresentationSource(
                    window: target.presentationWindow,
                    ownerView: target.anchor?.buttonView
                )
            let sidebarTransientSessionToken =
                sidebarTransientSessionCoordinator.beginSession(
                    kind: .extensionActionPopover,
                    source: sidebarTransientPresentationSource,
                    path: "ExtensionActionPopupCoordinator.present"
                )
            let session = ExtensionActionPopupSession(
                claim: claim,
                evidence: evidence,
                action: action,
                popover: popover,
                popupWebView: popupWebView,
                sourceReceipt: sourceReceipt,
                focusReceipt: focusReceipt,
                telemetrySnapshot: telemetrySnapshot,
                completion: completion,
                sidebarTransientSessionCoordinator:
                    sidebarTransientSessionCoordinator,
                sidebarTransientSessionToken: sidebarTransientSessionToken,
                popoverDidClose: { [weak retirement] claim, popover in
                    retirement?.popoverDidClose(
                        claim: claim,
                        popover: popover
                    )
                },
                popoverWillClose: { [weak retirement] claim, popover in
                    retirement?.popoverWillClose(
                        claim: claim,
                        popover: popover
                    )
                }
            )
            guard sessions.stage(session, for: claim) else {
                session.retirePresentation(closePhysicalPopup: false)
                completion.settle(CancellationError())
                return
            }
            session.observePopoverClosing()
            guard sessions.isPending(claim),
                  admission.isCurrent(evidence),
                  targetCapture.isCurrent(target)
            else {
                retirement.failPending(claim, error: CancellationError())
                return
            }
            let resolution = anchorResolver
                .presentResolvedExtensionActionPopup(
                    popover,
                    target: target,
                    isCurrent: {
                        sessions.isPending(claim)
                            && admission.isCurrent(evidence)
                            && targetCapture.isCurrent(target)
                            && mutationIsBlocked(evidence.profileID) == false
                            && action.webExtensionContext === evidence.context
                            && popupWebView.configuration.webExtensionController
                                === evidence.controller
                            && popupWebView.configuration.websiteDataStore
                                === contextConfiguration.websiteDataStore
                    }
                )
            guard resolution.anchorResolved,
                  popover.isShown,
                  sessions.isPending(claim),
                  admission.isCurrent(evidence),
                  targetCapture.isCurrent(target),
                  mutationIsBlocked(evidence.profileID) == false,
                  action.webExtensionContext === evidence.context,
                  popupWebView.configuration.webExtensionController
                      === evidence.controller,
                  popupWebView.configuration.websiteDataStore
                      === contextConfiguration.websiteDataStore
            else {
                let error: any Error = resolution.anchorResolved
                    ? CancellationError()
                    : ExtensionManagerCallbackError
                        .actionPopupAnchorUnavailable(
                            anchorSource: resolution.anchorSource?.rawValue
                        ).nsError()
                retirement.failPending(claim, error: error)
                return
            }
            guard let commit = sessions.commit(session) else {
                retirement.failPending(claim, error: CancellationError())
                return
            }
            retirement.execute(commit.replaced)
            guard commitRecorder.record(
                session,
                resolution: resolution,
                phase: commit.phase
            ), sessions.settleCommitted(session) else {
                completion.settle(CancellationError())
                return
            }
            completion.settle(nil)
        }
        guard sessions.attach(task, to: claim) else {
            task.cancel()
            completion.settle(CancellationError())
            return
        }
    }
}
