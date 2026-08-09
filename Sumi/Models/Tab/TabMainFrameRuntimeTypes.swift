import Foundation
import SumiWebRuntime
import WebKit

extension URL {
    var isSumiBlankDocumentURL: Bool {
        absoluteString.caseInsensitiveCompare("about:blank") == .orderedSame
    }
}

struct BlankDocumentAdmission: Equatable {
    enum Source: Equatable {
        case explicitUserCommand
        case siteNavigation(origin: URL?)
        case popup(openerPageID: UUID?, origin: URL?)
        case history
        case nativeSessionSnapshot
    }

    let id: UUID
    let source: Source
}

struct TabMainFrameNavigationIntent: Equatable {
    let revision: UInt64
    let targetURL: URL
    let blankAdmission: BlankDocumentAdmission?

    init(
        revision: UInt64,
        targetURL: URL,
        blankAdmission: BlankDocumentAdmission? = nil
    ) {
        self.revision = revision
        self.targetURL = targetURL
        self.blankAdmission = blankAdmission
    }
}

struct TabMainFramePreparedLoadTicket: Equatable {
    let revision: UInt64
    let id: UUID
    let webViewID: ObjectIdentifier
}

enum TabMainFramePendingAttemptPhase: Equatable {
    case preparing(ticketID: UUID)
    case deferred
    case submitted
}

/// Immutable witness for the one browser-owned main-frame attempt before its
/// ownership transfers into WebKit's navigation lifecycle.
struct TabMainFramePendingAttemptOwner: Equatable {
    let intent: TabMainFrameNavigationIntent
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
    let phase: TabMainFramePendingAttemptPhase

    init(
        intent: TabMainFrameNavigationIntent,
        lease: TabMainFrameSubmissionLease
    ) {
        self.intent = intent
        documentGeneration = lease.documentGeneration
        participantID = lease.participantID
        webViewID = lease.webViewID
        phase = .submitted
    }

    init(
        intent: TabMainFrameNavigationIntent,
        documentGeneration: UInt64,
        participantID: UUID,
        webViewID: ObjectIdentifier,
        phase: TabMainFramePendingAttemptPhase
    ) {
        self.intent = intent
        self.documentGeneration = documentGeneration
        self.participantID = participantID
        self.webViewID = webViewID
        self.phase = phase
    }
}

enum TabMainFramePendingAttemptStatus: Equatable {
    case unsubmitted(TabMainFrameNavigationIntent)
    case waiting(TabMainFramePendingAttemptOwner)
    case submitted(TabMainFramePendingAttemptOwner)
}

enum TabMainFramePendingAttemptAdmission: Equatable {
    case waiting(TabMainFramePendingAttemptOwner)
    case coalesced(TabMainFramePendingAttemptOwner)
    case rejected
}

enum TabMainFramePendingAttemptTerminalReason: Equatable {
    case cancelled
    case failed
    case departed
    case superseded
}

struct TabMainFramePendingAttemptSettlement: Equatable {
    let owner: TabMainFramePendingAttemptOwner
    let reason: TabMainFramePendingAttemptTerminalReason
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
    let hasCommittedDocument: Bool
    let needsSharedCommitEffects: Bool
    let needsSharedFinishEffects: Bool
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let webViewID: ObjectIdentifier
    let source: TabMainFrameAuthorityContinuationSource

    init(
        webView: WKWebView,
        navigationID: ObjectIdentifier?,
        targetURL: URL,
        isPDF: Bool,
        isCompleted: Bool,
        hasCommittedDocument: Bool = false,
        needsSharedCommitEffects: Bool,
        needsSharedFinishEffects: Bool,
        revision: UInt64,
        documentGeneration: UInt64,
        participantID: UUID,
        webViewID: ObjectIdentifier,
        source: TabMainFrameAuthorityContinuationSource
    ) {
        self.webView = webView
        self.navigationID = navigationID
        self.targetURL = targetURL
        self.isPDF = isPDF
        self.isCompleted = isCompleted
        self.hasCommittedDocument = hasCommittedDocument
        self.needsSharedCommitEffects = needsSharedCommitEffects
        self.needsSharedFinishEffects = needsSharedFinishEffects
        self.revision = revision
        self.documentGeneration = documentGeneration
        self.participantID = participantID
        self.webViewID = webViewID
        self.source = source
    }

    static func == (
        lhs: TabMainFrameAuthorityContinuation,
        rhs: TabMainFrameAuthorityContinuation
    ) -> Bool {
        lhs.webView === rhs.webView
            && lhs.navigationID == rhs.navigationID
            && lhs.targetURL == rhs.targetURL
            && lhs.isPDF == rhs.isPDF
            && lhs.isCompleted == rhs.isCompleted
            && lhs.hasCommittedDocument == rhs.hasCommittedDocument
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

enum TabWebContentProcessRecoveryDisposition: Equatable {
    case duplicate
    case pendingActivation
    case deliver
    case failed
}

struct TabWebContentProcessRecoveryPlan: Equatable {
    let disposition: TabWebContentProcessRecoveryDisposition
    let scope: TabWebContentProcessRecoveryScope
    let authorityContinuation: TabMainFrameAuthorityContinuation?
}

struct PageRecoverySessionSnapshot: Equatable {
    let residence: WebViewResidence
    let residenceGeneration: UInt64
    let profileID: UUID?
    let dataStoreIdentity: PageSessionDataStoreIdentity
    let committedRevision: UInt64
    let destination: URL
    let data: Data
}

enum PageRecoveryResidencePhase: Equatable {
    case pendingActivation
    case waitingForOwner
    case recovering(navigationID: ObjectIdentifier)
    case failed
}

struct PageRecoveryResidenceState: Equatable {
    let phase: PageRecoveryResidencePhase
    let destination: URL
    let snapshot: PageRecoverySessionSnapshot?

    var isFailure: Bool { phase == .failed }
    var ownsFutureOrSubmittedNavigation: Bool {
        switch phase {
        case .pendingActivation, .waitingForOwner, .recovering:
            true
        case .failed:
            false
        }
    }
}
