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
    }
}

struct TabMainFrameCommitSnapshotClaim: Equatable {
    let role: TabMainFrameLifecycleRole
    let shouldPublishSharedEffects: Bool
}

struct TabMainFrameCommitPublication {
    let webView: WKWebView
    let navigationID: ObjectIdentifier
    let targetURL: URL
    let isPDF: Bool
}

enum TabMainFrameCommitDecision {
    case stale
    case recordedReplica
    case alreadyPublished
    case publish(TabMainFrameCommitPublication)
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
