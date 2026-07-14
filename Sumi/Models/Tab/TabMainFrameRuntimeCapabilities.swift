import Foundation
import WebKit

/// State-free views of one `TabMainFrameRuntimeTransaction`. They narrow what
/// each collaborator can settle; none is an independent lifecycle authority.
@MainActor
protocol TabMainFrameSubmissionSettlement: AnyObject {
    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64?

    func bindSubmittedLoad(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        matching lease: TabMainFrameSubmissionLease?
    ) -> Bool

    func failSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> TabMainFrameNavigationAbortResult

    func restoreDeferredLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease?
    )
}

@MainActor
protocol TabMainFrameLifecycleSettlement: AnyObject {
    func role(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> TabMainFrameLifecycleRole

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject
    ) -> TabMainFrameLifecycleRole

    func settleCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject,
        committedURL: URL
    ) -> TabMainFrameTransitionDecision<TabMainFrameCommitPublication>

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication
    ) -> Bool

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject
    ) -> TabMainFrameTransitionDecision<TabMainFrameActiveAuthorityLease>

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject
    ) -> TabMainFrameTransitionDecision<TabMainFrameActiveAuthorityLease>

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject
    ) -> TabMainFrameTransitionDecision<URL>

    func remainsCurrent(_ lease: TabMainFrameActiveAuthorityLease) -> Bool

    func settleFinish(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        terminalURL: URL?
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication>

    func consumeFinishPublication(
        _ publication: TabMainFrameFinishPublication
    ) -> Bool

    func remainsCurrent(_ lease: TabMainFrameCompletedAuthorityLease) -> Bool

    func settleSameDocument(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        presentationURL: URL
    ) -> TabMainFrameTransitionDecision<TabMainFrameSameDocumentPublication>

    func consumeSameDocumentPublication(
        _ publication: TabMainFrameSameDocumentPublication
    ) -> Bool

    func noteResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier, navigationLifetime: AnyObject
    )
}

@MainActor
protocol TabMainFramePromotionSettlement: AnyObject {
    func claimSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool

    func prepareSharedFinishPublication(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication>

    func consumeFinishPublication(
        _ publication: TabMainFrameFinishPublication
    ) -> Bool

    func remainsCurrent(_ lease: TabMainFrameCompletedAuthorityLease) -> Bool

    func remainsCurrent(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool
}
