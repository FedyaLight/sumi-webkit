import Foundation

@MainActor
final class TabExtensionRuntimeState {
    var mutationRevision: UInt64 = 0
    var controllerGeneration: ExtensionTabPublicationRevision?
    var documentSequence: UInt64 = 0
    var committedMainDocumentURL: URL?
    /// Document sequence when `didOpenTab` last succeeded; `nil` if never notified.
    var openNotifiedDocumentSequence: UInt64?
    /// Profile extension-context binding generation observed at the last pre-commit `didOpenTab`.
    var openNotifiedContextBindingGeneration: UInt64?
    /// Whether every enabled content-script extension context was loaded when `didOpenTab` last ran.
    var openNotifiedContextReadiness: TabExtensionContextReadiness = .notNotified
    var lastReportedURL: URL?
    var lastReportedLoading: TabExtensionLoadingReport = .notReported
    var lastReportedTitle: String?
    var didReportOpenForGeneration: ExtensionTabPublicationRevision?
    var eligibleGeneration: ExtensionTabPublicationRevision?
    var acceptsFutureOpenPublications = true
    var preparedWindowPrepublicationToken: TabExtensionPrepublicationToken?
    weak var committedWindowPrepublicationToken: TabExtensionPrepublicationToken?
    weak var awaitingSupersedingOpenToken: TabExtensionPrepublicationToken?
    var committedWindowPrepublicationTokenIdentity: ObjectIdentifier?
    var openPublicationClaim: TabExtensionOpenPublicationClaim?
    var settledOpenPublicationClaimIdentity: ObjectIdentifier?
}

enum TabExtensionContextReadiness: Equatable, Sendable {
    case notNotified
    case unknown
    case loaded
    case missing
}

enum TabExtensionLoadingReport: Equatable {
    case notReported
    case reported(Bool)

    var hasReported: Bool {
        self != .notReported
    }

    func matches(_ isLoadingComplete: Bool) -> Bool {
        self == .reported(isLoadingComplete)
    }
}

struct TabExtensionPrepublicationSnapshot {
    let controllerGeneration: ExtensionTabPublicationRevision?
    let documentSequence: UInt64
    let committedMainDocumentURL: URL?
    let openNotifiedDocumentSequence: UInt64?
    let openNotifiedContextBindingGeneration: UInt64?
    let openNotifiedContextReadiness: TabExtensionContextReadiness
    let lastReportedURL: URL?
    let lastReportedLoading: TabExtensionLoadingReport
    let lastReportedTitle: String?
    let didReportOpenForGeneration: ExtensionTabPublicationRevision?
    let eligibleGeneration: ExtensionTabPublicationRevision?
    let committedWindowPrepublicationTokenIdentity: ObjectIdentifier?
    let committedWindowPrepublicationToken: TabExtensionPrepublicationToken?
    let openPublicationClaim: TabExtensionOpenPublicationClaim?
    let settledOpenPublicationClaimIdentity: ObjectIdentifier?
}

enum TabExtensionPrepublicationPhase: Equatable {
    case prepared
    case awaitingSupersedingOpen
    case supersededByOpen
    case committed
    case finished
}

/// Opaque, single-use rollback token for extension state prepared before a
/// browser window crosses its publication boundary.
@MainActor
final class TabExtensionPrepublicationToken {
    let sourceIdentity: ObjectIdentifier
    let generation: ExtensionTabPublicationRevision
    let snapshot: TabExtensionPrepublicationSnapshot
    var phase = TabExtensionPrepublicationPhase.prepared
    var committedMutationRevision: UInt64?
    var openPublicationClaimIdentity: ObjectIdentifier?
    var supersedingOpenPublicationClaimIdentity: ObjectIdentifier?

    init(
        sourceIdentity: ObjectIdentifier,
        generation: ExtensionTabPublicationRevision,
        snapshot: TabExtensionPrepublicationSnapshot
    ) {
        self.sourceIdentity = sourceIdentity
        self.generation = generation
        self.snapshot = snapshot
    }
}

/// Opaque identity of one exact `didOpenTab` publication. Runtime generation
/// alone is not an identity: a Tab can close and reopen without a reload.
@MainActor
final class TabExtensionOpenPublicationClaim {
    let sourceIdentity: ObjectIdentifier
    let generation: ExtensionTabPublicationRevision
    private let publisher: AnyObject?
    private let adapter: AnyObject?

    init(
        sourceIdentity: ObjectIdentifier,
        generation: ExtensionTabPublicationRevision,
        publisher: AnyObject?,
        adapter: AnyObject?
    ) {
        self.sourceIdentity = sourceIdentity
        self.generation = generation
        self.publisher = publisher
        self.adapter = adapter
    }

    func representsPublication(
        publisher: AnyObject,
        adapter: AnyObject
    ) -> Bool {
        self.publisher === publisher && self.adapter === adapter
    }

    func publicationAuthority()
        -> (publisher: AnyObject, adapter: AnyObject)? {
        guard let publisher, let adapter else { return nil }
        return (publisher, adapter)
    }
}

/// Opaque snapshot authorizing one exact open-publication invalidation after a
/// synchronous external callback. Exact token identities and phases also
/// protect window-publication state that does not yet have an open claim.
struct TabExtensionOpenPublicationInvalidationWitness {
    let sourceIdentity: ObjectIdentifier
    let generation: ExtensionTabPublicationRevision?
    let claimIdentity: ObjectIdentifier?
    let preparedTokenIdentity: ObjectIdentifier?
    let preparedTokenPhase: TabExtensionPrepublicationPhase?
    let committedTokenIdentity: ObjectIdentifier?
    let committedTokenPhase: TabExtensionPrepublicationPhase?
    let awaitingTokenIdentity: ObjectIdentifier?
    let awaitingTokenPhase: TabExtensionPrepublicationPhase?
}

struct TabExtensionPageIdentity: Equatable, Sendable {
    let tabId: String
    let pageGeneration: String
    let pageId: String
}

struct TabExtensionDocumentBindingSnapshot: Equatable {
    let documentSequence: UInt64
    let committedMainDocumentURL: URL?
    let openNotifiedDocumentSequence: UInt64?
    let openNotifiedContextBindingGeneration: UInt64?
    let openNotifiedContextReadiness: TabExtensionContextReadiness
}
