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
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole

    func settleCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL
    ) -> TabMainFrameCommitDecision

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication
    ) -> Bool

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease>

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease>

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<URL>

    func remainsCurrent(_ lease: TabMainFrameActiveAuthorityLease) -> Bool

    func claimAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool
    ) -> TabMainFrameLifecycleRole

    func claimSharedFinishEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool

    func noteResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    )

    func finish(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    )
}

@MainActor
protocol TabMainFramePromotionSettlement: AnyObject {
    func claimSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool

    func claimSharedFinishEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool

    func remainsCurrent(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool
}
