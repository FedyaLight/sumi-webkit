import Foundation
import SumiWebRuntime
import WebKit

@MainActor
protocol TabCommittedDocumentSuspensionEffects: AnyObject {
    func committedDocumentSuspensionDecisionDidChange(reason: String)
}

/// Exact committed-document capability for a tab. It is the only production
/// holder of the durable ledger. Every document/eligibility mutation runs
/// inside one semantic transition, so activation and eligibility effects
/// cannot observe a half-applied main-frame lifecycle operation.
@MainActor
final class TabCommittedDocumentRuntime {
    enum Reason: String {
        case documentCommit = "document-commit"
        case authorityPromotion = "document-authority-promotion"
        case terminalCompletion = "document-terminal-completion"
        case replicaDeparture = "document-replica-departure"
        case navigationAbort = "document-navigation-abort"
        case navigationCancel = "document-navigation-cancel"
        case submissionFailure = "document-submission-rollback"
        case processRecovery = "web-content-process-recovery"
        case sameDocumentPresentation = "same-document-presentation"
        case suspensionReport = "document-suspension-state"
    }

    private let evidenceSource: any TabMainFrameDocumentEvidenceSource
    private let ledger: TabCommittedDocumentLedger
    private var isApplyingTransition = false
    private var transitionMutatedDocument = false
    private weak var suspensionEffects: (
        any TabCommittedDocumentSuspensionEffects
    )?

    init(
        initialURL: URL,
        evidenceSource: any TabMainFrameDocumentEvidenceSource
    ) {
        self.evidenceSource = evidenceSource
        self.ledger = TabCommittedDocumentLedger(initialURL: initialURL)
    }

    func attachSuspensionEffects(
        _ effects: any TabCommittedDocumentSuspensionEffects
    ) {
        precondition(
            suspensionEffects == nil || suspensionEffects === effects,
            "Committed-document suspension effects are installed once"
        )
        suspensionEffects = effects
    }

    func performTransition<Result>(
        reason: Reason,
        _ transition: () -> Result
    ) -> Result {
        precondition(
            isApplyingTransition == false,
            "Committed-document transitions cannot be nested"
        )
        let previousDecision = ledger.suspensionDecision()
        isApplyingTransition = true
        transitionMutatedDocument = false
        let result = transition()
        let mutatedDocument = transitionMutatedDocument
        isApplyingTransition = false
        guard mutatedDocument else { return result }
        activatePendingSensors()
        guard ledger.suspensionDecision() != previousDecision else {
            return result
        }
        suspensionEffects?.committedDocumentSuspensionDecisionDidChange(
            reason: reason.rawValue
        )
        return result
    }

    func recordReplica(_ evidence: TabCommittedDocumentEvidence) {
        beginDocumentMutation()
        ledger.recordReplica(evidence)
    }

    func recordReplicas(_ evidence: [TabCommittedDocumentEvidence]) {
        evidence.forEach(recordReplica)
    }

    func recordCommit(
        _ evidence: TabCommittedDocumentEvidence,
        publishesCanonicalDocument: Bool
    ) {
        beginDocumentMutation()
        ledger.recordReplica(evidence)
        if publishesCanonicalDocument {
            ledger.adoptCanonicalDocument(evidence)
        }
    }

    func adoptCanonicalDocument(_ evidence: TabCommittedDocumentEvidence) {
        beginDocumentMutation()
        ledger.adoptCanonicalDocument(evidence)
    }

    func updatePresentation(_ url: URL, on webView: WKWebView) {
        beginDocumentMutation()
        ledger.updatePresentation(url, on: webView)
    }

    func removeWebView(_ webView: WKWebView) {
        beginDocumentMutation()
        ledger.removeWebView(webView)
    }

    func removeWebViews(
        _ webViews: [WKWebView],
        preferredSourceWebView: WKWebView?
    ) {
        beginDocumentMutation()
        ledger.removeWebViews(
            webViews,
            preferredSourceWebView: preferredSourceWebView
        )
    }

    func prepareRollbackSnapshot() -> TabCommittedDocumentRollbackSnapshot {
        beginDocumentMutation()
        return ledger.rollbackSnapshot()
    }

    func adoptRehydratedEvidence(
        _ evidence: [TabCommittedDocumentEvidence],
        authorityWebViewID: ObjectIdentifier?
    ) {
        beginDocumentMutation()
        ledger.adoptRehydratedEvidence(
            evidence,
            authorityWebViewID: authorityWebViewID
        )
    }

    func lease(for webView: WKWebView) -> TabMainFrameDocumentLease? {
        guard let proof = evidenceSource.documentProof(for: webView) else {
            return nil
        }
        return ledger.documentLease(
            matching: proof.evidence,
            isAuthority: proof.isAuthority
        )
    }

    func hasCommittedDocument(on webView: WKWebView) -> Bool {
        ledger.hasCommittedDocument(on: webView)
    }

    /// Exact canonical-document identity for external admission evidence.
    var authorityProof: TabCommittedDocumentAuthorityProof {
        ledger.authorityProof()
    }

    var suspensionDecision: TabDocumentSuspensionDecision {
        ledger.suspensionDecision()
    }

    func suspensionActivationToken(for webView: WKWebView) -> String? {
        guard let lease = lease(for: webView) else { return nil }
        return ledger.suspensionToken(for: webView, matching: lease)
    }

    @discardableResult
    func recordSuspensionReport(
        _ report: TabDocumentSuspensionReport,
        from webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> Bool {
        performAcceptedMutation(reason: .suspensionReport) {
            guard let currentLease = self.lease(for: webView),
                  Self.matches(currentLease, lease, includingDocument: true)
            else {
                return false
            }
            return self.ledger.recordSuspensionReport(
                report,
                from: webView,
                matching: currentLease
            )
        }
    }

    func sourceWebView() -> WKWebView? {
        ledger.sourceWebView()
    }

    private func activatePendingSensors() {
        for activation in ledger.takePendingSuspensionActivations() {
            let webView = activation.webView
            let token = activation.token
            let epoch = activation.epoch
            SumiDocumentSuspensionSensorUserScript.activateCommittedDocument(
                on: webView,
                token: token,
                epoch: epoch,
                completion: { [weak self, weak webView] activated in
                    guard activated == false,
                          let self,
                          let webView,
                          self.ledger.suspensionActivationDidFail(
                              for: webView,
                              token: token,
                              epoch: epoch
                          ) else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        self?.activatePendingSensors()
                    }
                }
            )
        }
    }

    private func performAcceptedMutation(
        reason: Reason,
        _ mutation: () -> Bool
    ) -> Bool {
        precondition(
            isApplyingTransition == false,
            "Committed-document transitions cannot be nested"
        )
        let previousDecision = ledger.suspensionDecision()
        isApplyingTransition = true
        let accepted = mutation()
        isApplyingTransition = false
        guard accepted else { return false }
        activatePendingSensors()
        if ledger.suspensionDecision() != previousDecision {
            suspensionEffects?.committedDocumentSuspensionDecisionDidChange(
                reason: reason.rawValue
            )
        }
        return true
    }

    private func beginDocumentMutation() {
        precondition(
            isApplyingTransition,
            "Committed-document mutation requires a semantic transition"
        )
        transitionMutatedDocument = true
    }

    private static func matches(
        _ current: TabMainFrameDocumentLease,
        _ supplied: TabMainFrameDocumentLease,
        includingDocument: Bool
    ) -> Bool {
        guard current.revision == supplied.revision,
              current.documentGeneration == supplied.documentGeneration,
              current.webViewID == supplied.webViewID,
              current.participantID == supplied.participantID else {
            return false
        }
        guard includingDocument else { return true }
        return WebRuntimeNavigationIdentity(current.committedURL)
                == WebRuntimeNavigationIdentity(supplied.committedURL)
            && current.isPDF == supplied.isPDF
    }
}

extension Tab: TabCommittedDocumentSuspensionEffects {
    func committedDocumentSuspensionDecisionDidChange(reason _: String) {
        navigationRuntime.lifecycleNavigationRuntime
            .reconcileDocumentSuspensionState(self)
    }
}
