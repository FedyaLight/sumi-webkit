import Foundation
import WebKit

/// Internal plans emitted while the runtime moves participant and authority
/// state. These values never grant callback publication authority.
enum TabMainFrameTransitionOutput {
    struct LifecycleAcceptance {
        let role: TabMainFrameLifecycleRole
        let beganNewIntent: Bool
    }

    struct FailedSubmissionRollback {
        let targetURL: URL
        let navigationStateSource: WKWebView?
    }

    struct AuthorityPromotion {
        let continuation: TabMainFrameAuthorityContinuation
        let targetURLToAdopt: URL?
        let migratedEvidence: [TabCommittedDocumentEvidence]
    }

    enum LifecycleRouting {
        case accepted(role: TabMainFrameLifecycleRole, targetURLToAdopt: URL?)
        case unmatched
        case retired
    }

    struct LifecycleDeparture {
        let removedParticipant: Bool
        let wasAuthoritative: Bool
    }

    enum LifecycleAbort {
        case ignored
        case participant
        case authority(AuthorityPromotion?)
    }

    enum ParticipantAbort {
        case ignored
        case participant
        case authority
    }

    struct Rehydration {
        let evidence: [TabCommittedDocumentEvidence]
        let authorityWebViewID: ObjectIdentifier?
    }

    struct Commit {
        let role: TabMainFrameLifecycleRole
        let evidence: TabCommittedDocumentEvidence?
        let publication: TabMainFrameCommitPublication?
    }
}
