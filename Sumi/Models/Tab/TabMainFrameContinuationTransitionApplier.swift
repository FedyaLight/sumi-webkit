import Foundation
import WebKit

/// Commits one continuation as a registry, authority, and effect-ledger
/// transaction. The complete plan is validated before any mutable owner is
/// changed, so an interleaved stale plan cannot leave a partial continuation.
@MainActor
final class TabMainFrameContinuationTransitionApplier {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let committer: TabMainFrameTransitionCommitter

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        committer: TabMainFrameTransitionCommitter
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.committer = committer
    }

    func routeLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL,
        continuationKind: TabMainFrameContinuationKind?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleRouting {
        guard participants.isRetiredNavigationIdentity(
            navigationID,
            lifetime: navigationLifetime
        ) == false else { return .retired }
        if participants.exactCompletedEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) != nil {
            return .retired
        }

        let webViewID = ObjectIdentifier(webView)
        let existingRole = lifecycleRole(
            webView: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
        if existingRole != .stale {
            guard participants.attachNavigationIdentityIfPossible(
                navigationID: navigationID,
                lifetime: navigationLifetime,
                webView: webView
            ) else { return .retired }
            return .accepted(role: existingRole, targetURLToAdopt: nil)
        }

        guard let continuationKind,
              let existingParticipant = participants.exactEntry(for: webView),
              existingParticipant.revision == currentIntent.revision else {
            return .unmatched
        }
        let previousNavigationID: ObjectIdentifier?
        switch existingParticipant.phase {
        case .active(let navigationID): previousNavigationID = navigationID
        case .completed: previousNavigationID = nil
        }
        let snapshot = authorityState.snapshot
        let ownsAuthority = TabMainFrameAuthorityReducer.ownsParticipant(
            in: snapshot,
            existingParticipant,
            webViewID: webViewID,
            previousNavigationID: previousNavigationID
        )
        guard let prepared = participants.prepareContinuation(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else { return .unmatched }
        guard let receipt = committer.commitContinuation(
            prepared,
            targetURL: targetURL,
            kind: continuationKind,
            ownsAuthority: ownsAuthority
        ) else { return .retired }
        guard receipt.participant.documentGeneration
                == authorityState.snapshot.documentGeneration,
              receipt.reduction.becomesAuthority else {
            return .accepted(role: .participant, targetURLToAdopt: nil)
        }
        return .accepted(role: .authority, targetURLToAdopt: targetURL)
    }

    private func lifecycleRole(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.exactEntry(for: webView),
              participant.phase == .active(navigationID: navigationID),
              participant.revision == currentIntent.revision else {
            return .stale
        }
        return TabMainFrameAuthorityReducer.lifecycleRole(
            in: authorityState.snapshot,
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }
}
