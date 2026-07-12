import Foundation

/// Issues and revalidates an immutable proof for either kind of completed
/// main-frame authority. Terminal and same-document settlement share this
/// identity rule without depending on each other's publication policy.
@MainActor
final class TabMainFrameCompletedAuthorityProof {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityReducer: TabMainFrameAuthorityReducer

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityReducer: TabMainFrameAuthorityReducer
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.authorityReducer = authorityReducer
    }

    func issue(
        for participant: TabMainFrameParticipantRegistry.Entry
    ) -> TabMainFrameCompletedAuthorityLease? {
        guard case .completed(let navigationID, let kind) = participant.phase else {
            return nil
        }
        return authorityState.completedLease(
            participantID: participant.id,
            webViewID: participant.webViewReference.identifier,
            navigationID: navigationID,
            completionKind: kind,
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            committedDocumentURL: participant.committedDocumentURL,
            presentationURL: participant.targetURL,
            isPDF: participant.isPDFResponse ?? false
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameCompletedAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard lease.revision == currentIntent.revision,
              lease.documentGeneration == authorityReducer.documentGeneration,
              let participant = participants[lease.webViewID],
              participant.id == lease.participantID,
              participant.revision == lease.revision,
              participant.documentGeneration == lease.documentGeneration,
              participant.phase == .completed(
                  navigationID: lease.navigationID,
                  kind: lease.completionKind
              ),
              participant.hasCommittedDocument == lease.hasCommittedDocument,
              participant.committedDocumentURL == lease.committedDocumentURL,
              participant.targetURL == lease.presentationURL,
              (participant.isPDFResponse ?? false) == lease.isPDF,
              participant.webViewReference.resolve() != nil else {
            return false
        }
        return authorityState.matches(lease)
    }
}
