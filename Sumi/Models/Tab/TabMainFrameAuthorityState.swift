import Foundation

/// Exact logical authority identity. Participant storage and lifecycle effects
/// remain in their dedicated components; this type owns only authority phase
/// and the epoch that invalidates work crossing a reentrant callback.
@MainActor
final class TabMainFrameAuthorityState {
    struct Value: Equatable {
        let revision: UInt64
        let webViewID: ObjectIdentifier
        var documentGeneration: UInt64
        var navigationID: ObjectIdentifier?
        var hasCommittedDocument: Bool
        var isCompleted: Bool
    }

    private(set) var current: Value?
    private var epoch: UInt64 = 0

    func replace(with replacement: Value?) {
        if sameIdentity(current, replacement) == false {
            epoch &+= 1
        }
        current = replacement
    }

    func markCommitted() {
        guard var committed = current,
              committed.hasCommittedDocument == false else { return }
        committed.hasCommittedDocument = true
        replace(with: committed)
    }

    func markCompleted() {
        guard var completed = current else { return }
        completed.navigationID = nil
        completed.isCompleted = true
        replace(with: completed)
    }

    func noteTargetMutation(webViewID: ObjectIdentifier, revision: UInt64) {
        guard current?.webViewID == webViewID,
              current?.revision == revision else { return }
        epoch &+= 1
    }

    func activeLease(
        participantID: UUID,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64,
        documentGeneration: UInt64,
        targetURL: URL
    ) -> TabMainFrameActiveAuthorityLease? {
        guard let current,
              current.revision == revision,
              current.documentGeneration == documentGeneration,
              current.webViewID == webViewID,
              current.navigationID == navigationID,
              current.isCompleted == false else {
            return nil
        }
        return TabMainFrameActiveAuthorityLease(
            revision: revision,
            documentGeneration: documentGeneration,
            participantID: participantID,
            webViewID: webViewID,
            navigationID: navigationID,
            targetURL: targetURL,
            hasCommittedDocument: current.hasCommittedDocument,
            authorityEpoch: epoch
        )
    }

    func matches(_ lease: TabMainFrameActiveAuthorityLease) -> Bool {
        guard lease.authorityEpoch == epoch,
              let current else { return false }
        return current.revision == lease.revision
            && current.documentGeneration == lease.documentGeneration
            && current.webViewID == lease.webViewID
            && current.navigationID == lease.navigationID
            && current.hasCommittedDocument == lease.hasCommittedDocument
            && current.isCompleted == false
    }

    func completedLease(
        participantID: UUID,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier?,
        completionKind: TabMainFrameCompletionKind,
        revision: UInt64,
        documentGeneration: UInt64,
        committedDocumentURL: URL?,
        presentationURL: URL,
        isPDF: Bool
    ) -> TabMainFrameCompletedAuthorityLease? {
        guard let current,
              current.revision == revision,
              current.documentGeneration == documentGeneration,
              current.webViewID == webViewID,
              current.navigationID == nil,
              current.isCompleted else {
            return nil
        }
        return TabMainFrameCompletedAuthorityLease(
            revision: revision,
            documentGeneration: documentGeneration,
            participantID: participantID,
            webViewID: webViewID,
            navigationID: navigationID,
            completionKind: completionKind,
            hasCommittedDocument: current.hasCommittedDocument,
            committedDocumentURL: committedDocumentURL,
            presentationURL: presentationURL,
            isPDF: isPDF,
            authorityEpoch: epoch
        )
    }

    func matches(_ lease: TabMainFrameCompletedAuthorityLease) -> Bool {
        guard lease.authorityEpoch == epoch,
              let current else { return false }
        return current.revision == lease.revision
            && current.documentGeneration == lease.documentGeneration
            && current.webViewID == lease.webViewID
            && current.navigationID == nil
            && current.hasCommittedDocument == lease.hasCommittedDocument
            && current.isCompleted
    }

    func matches(epoch expectedEpoch: UInt64) -> Bool {
        epoch == expectedEpoch
    }

    var currentEpoch: UInt64 { epoch }

    private func sameIdentity(_ lhs: Value?, _ rhs: Value?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            return lhs.revision == rhs.revision
                && lhs.webViewID == rhs.webViewID
                && lhs.documentGeneration == rhs.documentGeneration
                && lhs.navigationID == rhs.navigationID
                && lhs.hasCommittedDocument == rhs.hasCommittedDocument
                && lhs.isCompleted == rhs.isCompleted
        default:
            return false
        }
    }
}
