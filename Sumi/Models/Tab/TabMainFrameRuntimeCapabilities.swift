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

    func recordCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool
    ) -> TabMainFrameCommitSnapshotClaim

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool

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

    @discardableResult
    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool?

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
}
