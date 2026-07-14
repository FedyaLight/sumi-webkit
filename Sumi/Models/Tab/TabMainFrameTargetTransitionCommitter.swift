import Foundation
import WebKit

/// Commits a presentation-target change only after the caller's exact
/// authority witness has been revalidated against the same mutable owners.
@MainActor
enum TabMainFrameTargetTransitionCommitter {
    static func commitActive(
        _ targetURL: URL,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        revision: UInt64,
        participants: TabMainFrameParticipantRegistry,
        state: TabMainFrameAuthorityState
    ) -> Bool {
        guard TabMainFrameAuthorityReducer.isExactAuthority(
            in: state.snapshot,
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            revision: revision
        ) else { return false }
        return commit(targetURL, webView: webView, participants: participants, state: state)
    }

    static func commitPromotion(
        _ targetURL: URL,
        continuation: TabMainFrameAuthorityContinuation,
        revision: UInt64,
        participants: TabMainFrameParticipantRegistry,
        state: TabMainFrameAuthorityState
    ) -> Bool {
        guard TabMainFrameAuthorityReducer.isCurrentAuthority(
            in: state.snapshot,
            continuation,
            revision: revision,
            participant: participants.exactEntry(for: continuation.webView)
        ) else { return false }
        return commit(
            targetURL,
            webView: continuation.webView,
            participants: participants,
            state: state
        )
    }

    private static func commit(
        _ targetURL: URL,
        webView: WKWebView,
        participants: TabMainFrameParticipantRegistry,
        state: TabMainFrameAuthorityState
    ) -> Bool {
        guard let mutation = participants.prepareTargetMutation(
            targetURL,
            webView: webView
        ) else { return false }
        let authority = mutation.previousEntry.targetURL != targetURL
            ? TabMainFrameAuthorityReducer.noteTargetMutation(
                in: state.snapshot,
                webViewID: ObjectIdentifier(webView),
                revision: mutation.previousEntry.revision
            )
            : TabMainFrameAuthorityPlan(nextSnapshot: state.snapshot, output: ())
        guard participants.canApply(mutation.plan),
              state.canApply(authority) else { return false }
        _ = participants.applyPrevalidated(mutation.plan)
        state.applyPrevalidated(authority)
        return true
    }
}
