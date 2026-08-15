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
