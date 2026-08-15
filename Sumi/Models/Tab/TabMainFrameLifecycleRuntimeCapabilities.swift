import Foundation
import WebKit

/// The WebKit callback capability of one main-frame runtime transaction.
/// Keeping this contract separate prevents lifecycle consumers from depending
/// on submission or promotion settlement APIs.
@MainActor
protocol TabMainFrameLifecycleSettlement: AnyObject {
    func role(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> TabMainFrameLifecycleRole

    func documentLease(
        _ lease: TabMainFrameDocumentLease,
        matches webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool

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
