import Foundation
import SumiWebRuntime

struct TabMainFrameAuthoritySnapshot {
    struct Value: Equatable {
        let revision: UInt64
        let webViewID: ObjectIdentifier
        var documentGeneration: UInt64
        var navigationID: ObjectIdentifier?
        var hasCommittedDocument: Bool
        var isCompleted: Bool
    }

    struct RedirectGenerationKey: Hashable {
        let sourceGeneration: UInt64
        let target: WebRuntimeNavigationIdentity
    }

    var authority: Value?
    var documentGeneration: UInt64
    var authorityEpoch: UInt64
    var redirectGenerationByKey: [RedirectGenerationKey: UInt64]
    fileprivate var stateRevision: UInt64

    static let initial = TabMainFrameAuthoritySnapshot(
        authority: nil,
        documentGeneration: 0,
        authorityEpoch: 0,
        redirectGenerationByKey: [:],
        stateRevision: 0
    )
}

struct TabMainFrameAuthorityPlan<Output> {
    fileprivate let expectedStateRevision: UInt64
    let nextSnapshot: TabMainFrameAuthoritySnapshot
    let output: Output

    init(nextSnapshot: TabMainFrameAuthoritySnapshot, output: Output) {
        self.expectedStateRevision = nextSnapshot.stateRevision
        self.nextSnapshot = nextSnapshot
        self.output = output
    }
}

/// Stores one immutable logical-authority snapshot. All next-state values are
/// produced by `TabMainFrameAuthorityReducer`; this store only atomically
/// applies a plan and issues exact epoch-bound leases from the resulting state.
@MainActor
final class TabMainFrameAuthorityState {
    private(set) var snapshot = TabMainFrameAuthoritySnapshot.initial
    var revision: UInt64 { snapshot.stateRevision }

    @discardableResult
    func canApply<Output>(_ plan: TabMainFrameAuthorityPlan<Output>) -> Bool {
        plan.expectedStateRevision == snapshot.stateRevision
    }

    @discardableResult
    func apply<Output>(_ plan: TabMainFrameAuthorityPlan<Output>) -> Output? {
        guard canApply(plan) else { return nil }
        applyPrevalidated(plan)
        return plan.output
    }

    func applyPrevalidated<Output>(_ plan: TabMainFrameAuthorityPlan<Output>) {
        precondition(canApply(plan), "authority plan must be prevalidated")
        var nextSnapshot = plan.nextSnapshot
        nextSnapshot.stateRevision &+= 1
        snapshot = nextSnapshot
    }

    func activeLease(
        in snapshot: TabMainFrameAuthoritySnapshot,
        participant: TabMainFrameParticipantRegistry.Entry
    ) -> TabMainFrameActiveAuthorityLease? {
        guard case .active(let navigationID) = participant.phase,
              participant.navigationIdentityReference?.identifier == navigationID,
              let current = snapshot.authority,
              current.revision == participant.revision,
              current.documentGeneration == participant.documentGeneration,
              current.webViewID == participant.webViewReference.identifier,
              current.navigationID == navigationID,
              current.isCompleted == false else {
            return nil
        }
        return TabMainFrameActiveAuthorityLease(
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            participantID: participant.id,
            webViewID: participant.webViewReference.identifier,
            navigationID: navigationID,
            targetURL: participant.targetURL,
            hasCommittedDocument: current.hasCommittedDocument,
            authorityEpoch: snapshot.authorityEpoch
        )
    }

    func matches(_ lease: TabMainFrameActiveAuthorityLease) -> Bool {
        guard lease.authorityEpoch == snapshot.authorityEpoch,
              let current = snapshot.authority else { return false }
        return current.revision == lease.revision
            && current.documentGeneration == lease.documentGeneration
            && current.webViewID == lease.webViewID
            && current.navigationID == lease.navigationID
            && current.hasCommittedDocument == lease.hasCommittedDocument
            && current.isCompleted == false
    }

    func completedLease(
        in snapshot: TabMainFrameAuthoritySnapshot,
        participant: TabMainFrameParticipantRegistry.Entry
    ) -> TabMainFrameCompletedAuthorityLease? {
        guard case .completed(let navigationID, let kind) = participant.phase,
              participant.navigationIdentityReference?.identifier == navigationID,
              let current = snapshot.authority,
              current.revision == participant.revision,
              current.documentGeneration == participant.documentGeneration,
              current.webViewID == participant.webViewReference.identifier,
              current.navigationID == nil,
              current.isCompleted else {
            return nil
        }
        return TabMainFrameCompletedAuthorityLease(
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            participantID: participant.id,
            webViewID: participant.webViewReference.identifier,
            navigationID: navigationID,
            completionKind: kind,
            hasCommittedDocument: current.hasCommittedDocument,
            committedDocumentURL: participant.committedDocumentURL,
            presentationURL: participant.targetURL,
            isPDF: participant.isPDFResponse ?? false,
            authorityEpoch: snapshot.authorityEpoch
        )
    }

    func matches(_ lease: TabMainFrameCompletedAuthorityLease) -> Bool {
        guard lease.authorityEpoch == snapshot.authorityEpoch,
              let current = snapshot.authority else { return false }
        return current.revision == lease.revision
            && current.documentGeneration == lease.documentGeneration
            && current.webViewID == lease.webViewID
            && current.navigationID == nil
            && current.hasCommittedDocument == lease.hasCommittedDocument
            && current.isCompleted
    }

    func matches(epoch expectedEpoch: UInt64) -> Bool { snapshot.authorityEpoch == expectedEpoch }
}
