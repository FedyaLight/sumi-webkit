import Foundation
import WebKit

struct TabMainFrameNavigationIntent: Equatable {
    let revision: UInt64
    let targetURL: URL
}

struct TabMainFramePreparedLoadTicket: Equatable {
    let revision: UInt64
    let id: UUID
    let webViewID: ObjectIdentifier
}

struct TabMainFrameSubmissionLease: Equatable {
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
}

struct TabMainFrameActiveAuthorityLease: Equatable {
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
    let navigationID: ObjectIdentifier
    let targetURL: URL
    let hasCommittedDocument: Bool
    let authorityEpoch: UInt64
}

enum TabMainFrameCompletionKind: Equatable {
    case document
    case sameDocument
}

/// Public callback vocabulary for every exact main-frame transition. A caller
/// either rejects stale evidence, records a non-authoritative participant,
/// observes an already settled publication, or receives the one value it may
/// publish. No callback family defines parallel settlement semantics.
enum TabMainFrameTransitionDecision<Value> {
    case stale
    case participant
    case alreadyPublished(Value?)
    case publish(Value)

    var value: Value? {
        switch self {
        case .stale, .participant: nil
        case .alreadyPublished(let value): value
        case .publish(let value): value
        }
    }
}

enum TabDeferredMainFrameLoadClaim: Equatable {
    case claimed
    case alreadyScheduled
    case submissionFailed
    case stale
}

enum TabMainFrameNavigationAbortResult: Equatable {
    case ignored
    case participant
    case authoritativeContinuation(TabMainFrameAuthorityContinuation)
    case authoritativeTerminated
    case authoritativeRollback(URL)
}

enum TabMainFrameAuthorityContinuationSource: Equatable {
    case pendingSubmission
    case lifecycle(authorityEpoch: UInt64)
}

struct TabMainFrameAuthorityContinuation: Equatable {
    let webView: WKWebView
    let navigationID: ObjectIdentifier?
    let targetURL: URL
    let isPDF: Bool
    let isCompleted: Bool
    let needsSharedCommitEffects: Bool
    let needsSharedFinishEffects: Bool
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
    let source: TabMainFrameAuthorityContinuationSource

    static func == (
        lhs: TabMainFrameAuthorityContinuation,
        rhs: TabMainFrameAuthorityContinuation
    ) -> Bool {
        lhs.webView === rhs.webView
            && lhs.navigationID == rhs.navigationID
            && lhs.targetURL == rhs.targetURL
            && lhs.isPDF == rhs.isPDF
            && lhs.isCompleted == rhs.isCompleted
            && lhs.needsSharedCommitEffects == rhs.needsSharedCommitEffects
            && lhs.needsSharedFinishEffects == rhs.needsSharedFinishEffects
            && lhs.revision == rhs.revision
            && lhs.documentGeneration == rhs.documentGeneration
            && lhs.participantID == rhs.participantID
            && lhs.webViewID == rhs.webViewID
            && lhs.source == rhs.source
    }
}

struct TabMainFrameCompletedAuthorityLease: Equatable {
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
    let navigationID: ObjectIdentifier?
    let completionKind: TabMainFrameCompletionKind
    let hasCommittedDocument: Bool
    let committedDocumentURL: URL?
    let presentationURL: URL
    let isPDF: Bool
    let authorityEpoch: UInt64
}

struct TabMainFrameCommitPermit: Hashable {
    let id: UUID
}

struct TabMainFrameCommitPublication {
    let webView: WKWebView
    let targetURL: URL
    let isPDF: Bool
    let authority: TabMainFrameActiveAuthorityLease
    let permit: TabMainFrameCommitPermit
}

struct TabMainFrameFinishPermit: Hashable {
    let id: UUID
}

struct TabMainFrameFinishPublication {
    let webView: WKWebView
    let presentationURL: URL
    let isPDF: Bool
    let authority: TabMainFrameCompletedAuthorityLease
    let permit: TabMainFrameFinishPermit
}

struct TabMainFrameSameDocumentPublication {
    let webView: WKWebView
    let presentationURL: URL
    let authority: TabMainFrameCompletedAuthorityLease
    let permit: TabMainFrameSameDocumentPermit
}

struct TabMainFrameSameDocumentPermit: Hashable {
    let id: UUID
}

struct TabMainFrameDocumentLease: Equatable {
    let revision: UInt64
    let documentGeneration: UInt64
    let webViewID: ObjectIdentifier
    let participantID: UUID
    let committedURL: URL
    let presentationURL: URL
    let isPDF: Bool
    let isAuthority: Bool
}

enum TabMainFrameLifecycleRole: Equatable {
    case stale
    case participant
    case authority

    var isParticipant: Bool { self != .stale }
    var isAuthority: Bool { self == .authority }
}

enum TabMainFrameContinuationKind: Equatable {
    case clientRedirect
    case requestRewrite
    case sameDocument
}

struct TabMainFrameRuntimeDepartureResult: Equatable {
    let removedParticipant: Bool
    let wasAuthoritative: Bool
    let continuation: TabMainFrameAuthorityContinuation?

    var hasReplacementAuthority: Bool { continuation != nil }
}

enum TabWebContentProcessRecoveryScope: Equatable {
    case replica(TabMainFrameNavigationIntent)
    case global(URL)
}

struct TabWebContentProcessRecoveryPlan: Equatable {
    let scope: TabWebContentProcessRecoveryScope
    let authorityContinuation: TabMainFrameAuthorityContinuation?
}
