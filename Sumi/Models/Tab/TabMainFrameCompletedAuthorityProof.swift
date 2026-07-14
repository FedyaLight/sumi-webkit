import Foundation
import WebKit

/// Issues and resolves immutable completed-authority proofs against the exact
/// registry and authority-state owners used by the lifecycle composition.
@MainActor
final class TabMainFrameCompletedAuthorityProof {
    enum Query {
        case lease(TabMainFrameCompletedAuthorityLease)
        case continuation(TabMainFrameAuthorityContinuation)
        case terminal(WKWebView, ObjectIdentifier, AnyObject)
    }

    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState
    ) {
        self.participants = participants
        self.authorityState = authorityState
    }

    func issue(for participant: TabMainFrameParticipantRegistry.Entry) -> TabMainFrameCompletedAuthorityLease? {
        authorityState.completedLease(
            in: authorityState.snapshot,
            participant: participant
        )
    }

    func participant(
        matching query: Query,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameParticipantRegistry.Entry? {
        switch query {
        case .lease(let lease):
            guard lease.revision == currentIntent.revision,
                  lease.documentGeneration == authorityState.snapshot.documentGeneration,
                  let participant = participants[lease.webViewID],
                  participant.matches(lease),
                  authorityState.matches(lease) else { return nil }
            return participant
        case .continuation(let continuation):
            let participant = participants.exactEntry(for: continuation.webView)
            return TabMainFrameAuthorityReducer.isCurrentAuthority(
                in: authorityState.snapshot,
                continuation,
                revision: currentIntent.revision,
                participant: participant
            ) ? participant : nil
        case let .terminal(webView, navigationID, navigationLifetime):
            guard let participant = participants.exactCompletedEntry(
                for: webView,
                navigationID: navigationID,
                navigationLifetime: navigationLifetime,
                revision: currentIntent.revision
            ), case .completed(_, .document) = participant.phase,
               issue(for: participant) != nil else { return nil }
            return participant
        }
    }
}
