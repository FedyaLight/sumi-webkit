import Foundation
import WebKit

struct TabMainFrameDocumentProof {
    let evidence: TabCommittedDocumentEvidence
    let isAuthority: Bool
}

@MainActor
protocol TabMainFrameDocumentEvidenceSource: AnyObject {
    func documentProof(for webView: WKWebView) -> TabMainFrameDocumentProof?
}

/// Operations that load-producing browser components may perform directly.
/// Semantic intent replacement and authority settlement remain available only
/// to `TabMainFrameRuntimeTransaction` through the concrete runtime.
@MainActor
protocol TabMainFrameLoads: AnyObject {
    var currentIntent: TabMainFrameNavigationIntent { get }

    func currentIntent(
        matching targetURL: URL
    ) -> TabMainFrameNavigationIntent?
    func currentIntent(revision: UInt64) -> TabMainFrameNavigationIntent?
    func isCurrent(_ intent: TabMainFrameNavigationIntent) -> Bool
    func isCurrent(revision: UInt64, targetURL: URL) -> Bool
    func submittedLease(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabMainFrameSubmissionLease?
    func beginPreparedLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePreparedLoadTicket?
    func finishPreparedLoad(_ ticket: TabMainFramePreparedLoadTicket)
    func cancelPreparedLoad(
        _ ticket: TabMainFramePreparedLoadTicket
    ) -> TabMainFramePendingAttemptSettlement?
    func claimPreparedSubmission(
        on webView: WKWebView,
        ticket: TabMainFramePreparedLoadTicket
    ) -> TabMainFrameSubmissionLease?
    func attemptStatus(
        on webView: WKWebView
    ) -> TabMainFramePendingAttemptStatus
    func markDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> Bool
    func deferAttempt(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePendingAttemptAdmission
    func clearDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    )
    func claimDirectSubmission(
        on webView: WKWebView
    ) -> TabMainFrameSubmissionLease?
    func claimDeferredSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabDeferredMainFrameLoadClaim
    func hasOutstandingLoad(on webView: WKWebView, targetURL: URL) -> Bool
    func loadingWebViews() -> [WKWebView]
    func admitsCommit(to committedURL: URL) -> Bool
}

/// Exact capability for a tab's semantic navigation intent and loads that have
/// not yet acquired a WKNavigation identity. It owns the pending-load ledger
/// and consults the one lifecycle machine before admitting or exposing work.
@MainActor
final class TabMainFrameLoadRuntime: TabMainFrameLoads,
    TabMainFrameDocumentEvidenceSource {
    private let ledger: TabMainFrameIntentLedger
    private let lifecycle: TabMainFrameLifecycleMachine

    init(initialURL: URL, lifecycle: TabMainFrameLifecycleMachine) {
        self.ledger = TabMainFrameIntentLedger(initialURL: initialURL)
        self.lifecycle = lifecycle
    }

    var currentIntent: TabMainFrameNavigationIntent {
        ledger.intent
    }

    func currentIntent(
        matching targetURL: URL
    ) -> TabMainFrameNavigationIntent? {
        ledger.current(matching: targetURL)
    }

    func currentIntent(revision: UInt64) -> TabMainFrameNavigationIntent? {
        ledger.current(revision: revision)
    }

    func isCurrent(_ intent: TabMainFrameNavigationIntent) -> Bool {
        ledger.isCurrent(intent)
    }

    func isCurrent(revision: UInt64, targetURL: URL) -> Bool {
        ledger.isCurrent(revision: revision, targetURL: targetURL)
    }

    func submittedLease(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabMainFrameSubmissionLease? {
        ledger.submittedLease(
            on: webView,
            revision: revision,
            targetURL: targetURL
        )
    }

    func beginPreparedLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePreparedLoadTicket? {
        ledger.beginPreparedLoad(
            on: webView,
            intent: intent,
            documentGeneration: lifecycle.documentGeneration,
            hasLifecycleParticipant: lifecycle.hasParticipant(
                on: webView,
                revision: intent.revision
            )
        )
    }

    func finishPreparedLoad(_ ticket: TabMainFramePreparedLoadTicket) {
        ledger.finishPreparedLoad(ticket)
    }

    func cancelPreparedLoad(
        _ ticket: TabMainFramePreparedLoadTicket
    ) -> TabMainFramePendingAttemptSettlement? {
        ledger.cancelPreparedLoad(ticket)
    }

    func claimPreparedSubmission(
        on webView: WKWebView,
        ticket: TabMainFramePreparedLoadTicket
    ) -> TabMainFrameSubmissionLease? {
        ledger.claimPreparedSubmission(
            on: webView,
            ticket: ticket,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: ledger.intent.revision
            )
        )
    }

    func attemptStatus(
        on webView: WKWebView
    ) -> TabMainFramePendingAttemptStatus {
        ledger.pendingAttemptStatus(on: webView)
    }

    func markDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> Bool {
        let authority = lifecycle.authorityState(revision: intent.revision)
        return ledger.markDeferredLoad(
            on: webView,
            intent: intent,
            documentGeneration: lifecycle.documentGeneration,
            isLifecycleAuthority: authority?.webViewID
                == ObjectIdentifier(webView)
        )
    }

    func deferAttempt(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePendingAttemptAdmission {
        if let owner = lifecycle.activeAttemptOwner(
            on: webView,
            currentIntent: intent
        ) {
            return .coalesced(owner)
        }
        let authority = lifecycle.authorityState(revision: intent.revision)
        return ledger.deferAttempt(
            on: webView,
            intent: intent,
            documentGeneration: lifecycle.documentGeneration,
            isLifecycleAuthority: authority?.webViewID
                == ObjectIdentifier(webView)
        )
    }

    func clearDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) {
        ledger.clearDeferredLoad(on: webView, intent: intent)
    }

    func claimDirectSubmission(
        on webView: WKWebView
    ) -> TabMainFrameSubmissionLease? {
        ledger.claimDirectSubmission(
            on: webView,
            documentGeneration: lifecycle.documentGeneration,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: ledger.intent.revision
            )
        )
    }

    func claimDeferredSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabDeferredMainFrameLoadClaim {
        ledger.claimDeferredSubmission(
            on: webView,
            revision: revision,
            targetURL: targetURL,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: ledger.intent.revision
            )
        )
    }

    func hasOutstandingLoad(on webView: WKWebView, targetURL: URL) -> Bool {
        ledger.hasOutstandingLoad(on: webView, targetURL: targetURL)
            || lifecycle.loadingWebViews(
                revision: ledger.intent.revision
            ).contains(where: { $0 === webView })
    }

    func loadingWebViews() -> [WKWebView] {
        let submitted = ledger.submittedWebViews()
        let active = lifecycle.loadingWebViews(revision: ledger.intent.revision)
        var seen = Set<ObjectIdentifier>()
        return (submitted + active).filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    func documentProof(for webView: WKWebView) -> TabMainFrameDocumentProof? {
        guard let proof = lifecycle.documentEvidence(
            for: webView,
            currentIntent: ledger.intent
        ) else {
            return nil
        }
        return TabMainFrameDocumentProof(
            evidence: proof.evidence,
            isAuthority: proof.isAuthority
        )
    }

    func beginExplicitIntent(
        to targetURL: URL,
        blankAdmission: BlankDocumentAdmission? = nil
    ) -> TabMainFrameNavigationIntent {
        ledger.beginExplicitIntent(
            to: targetURL,
            blankAdmission: blankAdmission
        )
    }

    func beginLifecycleIntent(
        to targetURL: URL,
        blankAdmission: BlankDocumentAdmission? = nil
    ) -> TabMainFrameNavigationIntent {
        ledger.beginLifecycleIntent(
            to: targetURL,
            blankAdmission: blankAdmission
        )
    }

    func admitBlankDocument(_ admission: BlankDocumentAdmission) {
        ledger.admitBlankDocument(admission)
    }

    func admitsCommit(to committedURL: URL) -> Bool {
        ledger.admitsCommit(to: committedURL)
    }

    func beginRollbackIntent(
        to targetURL: URL
    ) -> TabMainFrameNavigationIntent {
        ledger.beginRollbackIntent(to: targetURL)
    }

    func updateTargetWithinRevision(_ targetURL: URL) {
        ledger.updateTargetWithinRevision(targetURL)
    }

    func canStartUnboundLifecycle(
        on webView: WKWebView,
        allowsUserInitiatedSupersession: Bool
    ) -> Bool {
        let revision = ledger.intent.revision
        return ledger.canStartUnboundLifecycle(
            on: webView,
            allowsUserInitiatedSupersession: allowsUserInitiatedSupersession,
            lifecycleAuthority: lifecycle.authorityState(revision: revision),
            hasLifecycleParticipant: lifecycle.hasParticipant(
                on: webView,
                revision: revision
            )
        )
    }

    func consumeSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> TabMainFrameIntentLedger.SubmissionBinding? {
        ledger.consumeSubmittedLoad(
            on: webView,
            matching: lease,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: ledger.intent.revision
            )
        )
    }

    func failSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> TabMainFrameIntentLedger.SubmissionFailure {
        ledger.failSubmittedLoad(on: webView, matching: lease)
    }

    func restoreDeferredLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease?
    ) -> Bool {
        ledger.restoreDeferredLoadAfterFailedSubmission(
            on: webView,
            revision: revision,
            targetURL: targetURL,
            matching: lease
        )
    }

    func departure(
        of webView: WKWebView
    ) -> TabMainFrameIntentLedger.PendingDeparture {
        ledger.departure(of: webView)
    }

    func departure(
        of webViews: [WKWebView]
    ) -> TabMainFrameIntentLedger.PendingDeparture {
        ledger.departure(of: webViews)
    }

    func promoteSubmittedAuthority(
        preferredWebViewID: ObjectIdentifier?
    ) -> TabMainFrameAuthorityContinuation? {
        ledger.promoteSubmittedAuthority(
            preferredWebViewID: preferredWebViewID
        )
    }

    func isCurrentPendingAuthority(
        _ continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        ledger.isCurrentPendingAuthority(continuation)
    }

    var hasPendingAuthority: Bool {
        ledger.hasPendingAuthority()
    }
}
