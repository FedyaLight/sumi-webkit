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
    fileprivate var lastReportedLoading: TabExtensionLoadingReport = .notReported
    var lastReportedTitle: String?
    var didReportOpenForGeneration: ExtensionTabPublicationRevision?
    var eligibleGeneration: ExtensionTabPublicationRevision?
    fileprivate var acceptsFutureOpenPublications = true
    fileprivate var preparedWindowPrepublicationToken:
        TabExtensionPrepublicationToken?
    fileprivate weak var committedWindowPrepublicationToken:
        TabExtensionPrepublicationToken?
    fileprivate weak var awaitingSupersedingOpenToken:
        TabExtensionPrepublicationToken?
    var committedWindowPrepublicationTokenIdentity: ObjectIdentifier?
    fileprivate var openPublicationClaim: TabExtensionOpenPublicationClaim?
    fileprivate var settledOpenPublicationClaimIdentity: ObjectIdentifier?
}

enum TabExtensionContextReadiness: Equatable, Sendable {
    case notNotified
    case unknown
    case loaded
    case missing
}

fileprivate enum TabExtensionLoadingReport: Equatable {
    case notReported
    case reported(Bool)

    var hasReported: Bool {
        self != .notReported
    }

    func matches(_ isLoadingComplete: Bool) -> Bool {
        self == .reported(isLoadingComplete)
    }
}

fileprivate struct TabExtensionPrepublicationSnapshot {
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
    let committedWindowPrepublicationToken:
        TabExtensionPrepublicationToken?
    let openPublicationClaim: TabExtensionOpenPublicationClaim?
    let settledOpenPublicationClaimIdentity: ObjectIdentifier?
}

fileprivate enum TabExtensionPrepublicationPhase: Equatable {
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
    fileprivate let sourceIdentity: ObjectIdentifier
    fileprivate let generation: ExtensionTabPublicationRevision
    fileprivate let snapshot: TabExtensionPrepublicationSnapshot
    fileprivate var phase = TabExtensionPrepublicationPhase.prepared
    fileprivate var committedMutationRevision: UInt64?
    fileprivate var openPublicationClaimIdentity: ObjectIdentifier?
    fileprivate var supersedingOpenPublicationClaimIdentity: ObjectIdentifier?

    fileprivate init(
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
    fileprivate let sourceIdentity: ObjectIdentifier
    fileprivate let generation: ExtensionTabPublicationRevision
    private let publisher: AnyObject?
    private let adapter: AnyObject?

    fileprivate init(
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
    fileprivate let sourceIdentity: ObjectIdentifier
    fileprivate let generation: ExtensionTabPublicationRevision?
    fileprivate let claimIdentity: ObjectIdentifier?
    fileprivate let preparedTokenIdentity: ObjectIdentifier?
    fileprivate let preparedTokenPhase: TabExtensionPrepublicationPhase?
    fileprivate let committedTokenIdentity: ObjectIdentifier?
    fileprivate let committedTokenPhase: TabExtensionPrepublicationPhase?
    fileprivate let awaitingTokenIdentity: ObjectIdentifier?
    fileprivate let awaitingTokenPhase: TabExtensionPrepublicationPhase?
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

@MainActor
final class TabExtensionPageRuntimeOwner {
    private let state = TabExtensionRuntimeState()

    var didNotifyOpenToExtensions: Bool {
        get { state.didReportOpenForGeneration != nil }
        set {
            guard newValue == false else { return }
            clearOpenNotificationGeneration()
        }
    }

    var documentSequence: UInt64 {
        get { state.documentSequence }
        set {
            invalidatePreparedWindowPrepublication()
            state.documentSequence = newValue
        }
    }

    var committedMainDocumentURL: URL? {
        get { state.committedMainDocumentURL }
        set {
            invalidatePreparedWindowPrepublication()
            state.committedMainDocumentURL = newValue
        }
    }

    var openNotifiedDocumentSequence: UInt64? {
        get { state.openNotifiedDocumentSequence }
        set {
            invalidatePreparedWindowPrepublication()
            state.openNotifiedDocumentSequence = newValue
        }
    }

    var openNotifiedContextBindingGeneration: UInt64? {
        get { state.openNotifiedContextBindingGeneration }
        set {
            invalidatePreparedWindowPrepublication()
            state.openNotifiedContextBindingGeneration = newValue
        }
    }

    var openNotifiedContextReadiness: TabExtensionContextReadiness {
        get { state.openNotifiedContextReadiness }
        set {
            invalidatePreparedWindowPrepublication()
            state.openNotifiedContextReadiness = newValue
        }
    }

    var lastReportedURL: URL? {
        get { state.lastReportedURL }
        set {
            invalidatePreparedWindowPrepublication()
            state.lastReportedURL = newValue
        }
    }

    var hasReportedLoadingComplete: Bool {
        state.lastReportedLoading.hasReported
    }

    var lastReportedTitle: String? {
        get { state.lastReportedTitle }
        set {
            invalidatePreparedWindowPrepublication()
            state.lastReportedTitle = newValue
        }
    }

    func clearOpenNotificationGeneration() {
        invalidatePreparedWindowPrepublication()
        state.didReportOpenForGeneration = nil
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        state.openPublicationClaim = nil
        state.settledOpenPublicationClaimIdentity = nil
    }

    func openPublicationInvalidationWitness()
        -> TabExtensionOpenPublicationInvalidationWitness {
        TabExtensionOpenPublicationInvalidationWitness(
            sourceIdentity: ObjectIdentifier(self),
            generation: state.didReportOpenForGeneration,
            claimIdentity: state.openPublicationClaim.map(ObjectIdentifier.init),
            preparedTokenIdentity: state.preparedWindowPrepublicationToken
                .map(ObjectIdentifier.init),
            preparedTokenPhase: state.preparedWindowPrepublicationToken?.phase,
            committedTokenIdentity: state.committedWindowPrepublicationToken
                .map(ObjectIdentifier.init),
            committedTokenPhase: state.committedWindowPrepublicationToken?.phase,
            awaitingTokenIdentity: state.awaitingSupersedingOpenToken
                .map(ObjectIdentifier.init),
            awaitingTokenPhase: state.awaitingSupersedingOpenToken?.phase
        )
    }

    /// Invalidates only the exact publication state observed immediately
    /// before a transaction crossed an external synchronous boundary.
    @discardableResult
    func invalidateOpenPublication(
        ifCurrent witness: TabExtensionOpenPublicationInvalidationWitness
    ) -> Bool {
        guard witness.sourceIdentity == ObjectIdentifier(self),
              witness.generation == state.didReportOpenForGeneration,
              witness.claimIdentity
                == state.openPublicationClaim.map(ObjectIdentifier.init),
              witness.preparedTokenIdentity
                == state.preparedWindowPrepublicationToken
                    .map(ObjectIdentifier.init),
              witness.preparedTokenPhase
                == state.preparedWindowPrepublicationToken?.phase,
              witness.committedTokenIdentity
                == state.committedWindowPrepublicationToken
                    .map(ObjectIdentifier.init),
              witness.committedTokenPhase
                == state.committedWindowPrepublicationToken?.phase,
              witness.awaitingTokenIdentity
                == state.awaitingSupersedingOpenToken
                    .map(ObjectIdentifier.init),
              witness.awaitingTokenPhase
                == state.awaitingSupersedingOpenToken?.phase
        else { return false }
        clearOpenNotificationGeneration()
        return true
    }

    func prepareGeneration(_ generation: ExtensionTabPublicationRevision) {
        guard state.controllerGeneration != generation else { return }
        // Generation preparation is still reversible until an ordinary
        // publisher reserves an exact open. A failed attachment must not strand
        // the surrounding window receipt in a non-rollbackable middle phase.
        if state.preparedWindowPrepublicationToken?.phase == .prepared
            || state.awaitingSupersedingOpenToken != nil {
            advanceMutationRevision()
        } else {
            invalidatePreparedWindowPrepublication()
        }
        state.controllerGeneration = generation
        state.lastReportedURL = nil
        state.lastReportedLoading = .notReported
        state.lastReportedTitle = nil
        state.didReportOpenForGeneration = nil
        state.eligibleGeneration = nil
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        state.openPublicationClaim = nil
        state.settledOpenPublicationClaimIdentity = nil
        clearOpenNotificationDocumentBinding()
    }

    func markEligible(for generation: ExtensionTabPublicationRevision) {
        if state.preparedWindowPrepublicationToken?.phase == .prepared {
            advanceMutationRevision()
        } else if state.awaitingSupersedingOpenToken != nil {
            advanceMutationRevision()
        } else {
            invalidatePreparedWindowPrepublication()
        }
        state.eligibleGeneration = generation
    }

    /// Makes a new Tab queryable by extension window adapters without emitting
    /// `didOpenTab`. The returned token must be committed after window
    /// publication or rolled back if the window transaction is rejected.
    func prepareForWindowPrepublication(
        generation: ExtensionTabPublicationRevision
    ) -> TabExtensionPrepublicationToken {
        // A replacement preparation inherits the original rollback point, not
        // the already-mutated state of the superseded preparation.
        let replacedPreparation = state.preparedWindowPrepublicationToken
        let rollbackSnapshot = replacedPreparation?.snapshot
            ?? windowPrepublicationSnapshot()
        replacedPreparation?.phase = .finished
        state.preparedWindowPrepublicationToken = nil
        state.awaitingSupersedingOpenToken?.phase = .finished
        state.awaitingSupersedingOpenToken = nil
        let token = TabExtensionPrepublicationToken(
            sourceIdentity: ObjectIdentifier(self),
            generation: generation,
            snapshot: rollbackSnapshot
        )
        prepareGeneration(generation)
        markEligible(for: generation)
        // A newer preparation temporarily owns rollback. Cancellation restores
        // the captured claim; successful handoff permanently supersedes it.
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        state.preparedWindowPrepublicationToken = token
        advanceMutationRevision()
        return token
    }

    @discardableResult
    func commitWindowPrepublication(
        _ token: TabExtensionPrepublicationToken,
        willEmitOpen: Bool
    ) -> Bool {
        guard canCommitWindowPrepublication(token) else { return false }
        state.preparedWindowPrepublicationToken = nil
        if willEmitOpen {
            token.phase = .committed
            state.committedWindowPrepublicationToken = token
            state.committedWindowPrepublicationTokenIdentity =
                ObjectIdentifier(token)
        } else {
            token.phase = .finished
        }
        advanceMutationRevision()
        return true
    }

    func canCommitWindowPrepublication(
        _ token: TabExtensionPrepublicationToken
    ) -> Bool {
        token.sourceIdentity == ObjectIdentifier(self)
            && token.phase == .prepared
            && state.preparedWindowPrepublicationToken === token
            && state.controllerGeneration == token.generation
            && state.eligibleGeneration == token.generation
    }

    /// Restores every field touched by generation preparation. The generation
    /// checks prevent a stale transaction from erasing a newer runtime bind.
    @discardableResult
    func rollbackWindowPrepublication(
        _ token: TabExtensionPrepublicationToken
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .prepared,
              state.preparedWindowPrepublicationToken === token
        else {
            return false
        }

        state.preparedWindowPrepublicationToken = nil
        restoreWindowPrepublicationSnapshot(token.snapshot)
        token.phase = .finished
        advanceMutationRevision()
        return true
    }

    /// Reverses only the exact initial-Tab open emitted after a committed
    /// window prepublication token. A newer generation or a second publisher
    /// makes the token stale instead of allowing it to erase newer state.
    @discardableResult
    func revokeCommittedWindowPrepublication(
        _ token: TabExtensionPrepublicationToken,
        openGeneration: ExtensionTabPublicationRevision
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .committed,
              token.generation == openGeneration,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              let claim = state.openPublicationClaim,
              token.openPublicationClaimIdentity == ObjectIdentifier(claim),
              state.controllerGeneration == openGeneration,
              state.eligibleGeneration == openGeneration,
              state.didReportOpenForGeneration == openGeneration
        else {
            return false
        }

        let restoredSnapshot = token.committedMutationRevision
            == state.mutationRevision
        if restoredSnapshot {
            restoreWindowPrepublicationSnapshot(token.snapshot)
        } else {
            // The open is still ours and must be balanced, but newer page,
            // reporting, or binding state must survive native rollback.
            state.didReportOpenForGeneration = nil
            state.committedWindowPrepublicationToken = nil
            state.committedWindowPrepublicationTokenIdentity = nil
            state.openPublicationClaim = nil
            state.settledOpenPublicationClaimIdentity = nil
        }
        token.phase = .finished
        advanceMutationRevision()
        return true
    }

    /// Releases a successfully published transaction token without restoring
    /// its snapshot. The did-open generation remains committed; only the
    /// temporary prepublication claim is retired.
    @discardableResult
    func finishCommittedWindowPrepublication(
        _ token: TabExtensionPrepublicationToken,
        openGeneration: ExtensionTabPublicationRevision
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .committed,
              token.generation == openGeneration,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              let claim = state.openPublicationClaim,
              token.openPublicationClaimIdentity == ObjectIdentifier(claim),
              state.controllerGeneration == openGeneration,
              state.eligibleGeneration == openGeneration,
              state.didReportOpenForGeneration == openGeneration
        else {
            return false
        }

        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        token.phase = .finished
        advanceMutationRevision()
        return true
    }

    @discardableResult
    func abortCommittedWindowPrepublicationBeforeOpen(
        _ token: TabExtensionPrepublicationToken
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .committed,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              state.controllerGeneration == token.generation,
              state.eligibleGeneration == token.generation,
              state.didReportOpenForGeneration
                == token.snapshot.didReportOpenForGeneration
        else {
            return false
        }
        restoreWindowPrepublicationSnapshot(token.snapshot)
        token.phase = .finished
        advanceMutationRevision()
        return true
    }

    /// Transfers a still-open exact publication to a surrounding window
    /// transaction without leaving a second snapshot restoration right alive.
    @discardableResult
    func finishWindowPrepublicationForDelegatedOpen(
        _ token: TabExtensionPrepublicationToken,
        claim: TabExtensionOpenPublicationClaim
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              claim.sourceIdentity == ObjectIdentifier(self),
              state.openPublicationClaim === claim,
              state.controllerGeneration == claim.generation,
              state.eligibleGeneration == claim.generation,
              state.didReportOpenForGeneration == claim.generation
        else {
            return false
        }

        switch token.phase {
        case .prepared:
            guard state.preparedWindowPrepublicationToken === token,
                  token.snapshot.openPublicationClaim === claim
            else {
                return false
            }
            state.preparedWindowPrepublicationToken = nil
        case .supersededByOpen:
            guard state.preparedWindowPrepublicationToken == nil,
                  token.supersedingOpenPublicationClaimIdentity
                    == ObjectIdentifier(claim),
                  token.openPublicationClaimIdentity
                    != ObjectIdentifier(claim)
            else {
                return false
            }
        case .awaitingSupersedingOpen, .committed, .finished:
            return false
        }
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        state.awaitingSupersedingOpenToken = nil
        token.phase = .finished
        advanceMutationRevision()
        return true
    }

    private func restoreWindowPrepublicationSnapshot(
        _ snapshot: TabExtensionPrepublicationSnapshot
    ) {
        state.controllerGeneration = snapshot.controllerGeneration
        state.documentSequence = snapshot.documentSequence
        state.committedMainDocumentURL = snapshot.committedMainDocumentURL
        state.openNotifiedDocumentSequence =
            snapshot.openNotifiedDocumentSequence
        state.openNotifiedContextBindingGeneration =
            snapshot.openNotifiedContextBindingGeneration
        state.openNotifiedContextReadiness =
            snapshot.openNotifiedContextReadiness
        state.lastReportedURL = snapshot.lastReportedURL
        state.lastReportedLoading = snapshot.lastReportedLoading
        state.lastReportedTitle = snapshot.lastReportedTitle
        state.didReportOpenForGeneration =
            snapshot.didReportOpenForGeneration
        state.eligibleGeneration = snapshot.eligibleGeneration
        state.committedWindowPrepublicationTokenIdentity =
            snapshot.committedWindowPrepublicationTokenIdentity
        state.committedWindowPrepublicationToken =
            snapshot.committedWindowPrepublicationToken
        state.awaitingSupersedingOpenToken = nil
        state.openPublicationClaim = snapshot.openPublicationClaim
        state.settledOpenPublicationClaimIdentity =
            snapshot.settledOpenPublicationClaimIdentity
    }

    func isEligible(for generation: ExtensionTabPublicationRevision) -> Bool {
        state.eligibleGeneration == generation
    }

    func hasDidOpenTabNotification(
        for generation: ExtensionTabPublicationRevision
    ) -> Bool {
        state.didReportOpenForGeneration == generation
    }

    func canPublishFutureOpenNotification() -> Bool {
        state.acceptsFutureOpenPublications
    }

    /// A failed extension-created Tab transaction is immediately discarded.
    /// Tombstone future opens before balancing its provisional callback so a
    /// WebView callback cannot reopen the doomed Tab in a newer generation.
    func retireFutureOpenPublications() {
        state.acceptsFutureOpenPublications = false
    }

    /// A raw open claim is reserved before crossing WebKit so teardown can
    /// balance it. Activation and property events require the stronger state:
    /// the exact callback returned and its transaction accepted the result.
    func hasSettledDidOpenTabNotification(
        for generation: ExtensionTabPublicationRevision
    ) -> Bool {
        guard state.didReportOpenForGeneration == generation,
              let claim = state.openPublicationClaim,
              claim.generation == generation
        else {
            return false
        }
        return state.settledOpenPublicationClaimIdentity
            == ObjectIdentifier(claim)
    }

    @discardableResult
    func settleDidOpenTabNotification(
        _ claim: TabExtensionOpenPublicationClaim,
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        guard claim.sourceIdentity == ObjectIdentifier(self),
              claim.generation == generation,
              state.openPublicationClaim === claim,
              state.didReportOpenForGeneration == generation
        else {
            return false
        }
        state.settledOpenPublicationClaimIdentity = ObjectIdentifier(claim)
        return true
    }

    func isCommittedWindowPrepublicationCurrent(
        _ token: TabExtensionPrepublicationToken,
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        token.sourceIdentity == ObjectIdentifier(self)
            && token.phase == .committed
            && token.generation == generation
            && state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token)
            && state.openPublicationClaim.map { ObjectIdentifier($0) }
                == token.openPublicationClaimIdentity
            && state.controllerGeneration == generation
            && state.eligibleGeneration == generation
            && state.didReportOpenForGeneration == generation
    }

    /// Atomically tombstones one exact generation before crossing WebKit's
    /// synchronous `didCloseTab` boundary. A nested reload or teardown sees
    /// the tombstone and cannot balance the same open twice.
    @discardableResult
    func claimDidOpenTabNotificationForClose(
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        guard state.didReportOpenForGeneration == generation,
              let closingClaim = state.openPublicationClaim
        else {
            return false
        }
        state.preparedWindowPrepublicationToken?.phase = .finished
        state.preparedWindowPrepublicationToken = nil
        advanceMutationRevision()
        if let committed = state.committedWindowPrepublicationToken,
           committed.phase == .committed {
            committed.phase = .awaitingSupersedingOpen
            state.awaitingSupersedingOpenToken = committed
        } else if let pending = state.awaitingSupersedingOpenToken,
                  pending.phase == .supersededByOpen,
                  pending.supersedingOpenPublicationClaimIdentity
                    == ObjectIdentifier(closingClaim) {
            // Keep the surrounding receipt's handoff capability alive across
            // repeated exact close -> reopen cycles until it settles.
            pending.phase = .awaitingSupersedingOpen
            pending.supersedingOpenPublicationClaimIdentity = nil
        }
        state.didReportOpenForGeneration = nil
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        state.openPublicationClaim = nil
        state.settledOpenPublicationClaimIdentity = nil
        return true
    }

    @discardableResult
    func claimDidOpenTabNotificationForClose(
        _ claim: TabExtensionOpenPublicationClaim,
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        guard claim.sourceIdentity == ObjectIdentifier(self),
              claim.generation == generation,
              state.openPublicationClaim === claim
        else {
            return false
        }
        return claimDidOpenTabNotificationForClose(generation: generation)
    }

    func currentOpenPublicationClaim(
        generation: ExtensionTabPublicationRevision
    ) -> TabExtensionOpenPublicationClaim? {
        guard state.didReportOpenForGeneration == generation,
              state.openPublicationClaim?.generation == generation
        else {
            return nil
        }
        return state.openPublicationClaim
    }

    func hasAnyDidOpenTabNotification() -> Bool {
        state.didReportOpenForGeneration != nil
    }

    func currentOpenNotificationGeneration()
        -> ExtensionTabPublicationRevision? {
        state.didReportOpenForGeneration
    }

    func currentPreparedGeneration() -> ExtensionTabPublicationRevision? {
        state.controllerGeneration
    }

    func currentEligibleGeneration() -> ExtensionTabPublicationRevision? {
        state.eligibleGeneration
    }

    func documentBindingSnapshot() -> TabExtensionDocumentBindingSnapshot {
        TabExtensionDocumentBindingSnapshot(
            documentSequence: state.documentSequence,
            committedMainDocumentURL: state.committedMainDocumentURL,
            openNotifiedDocumentSequence: state.openNotifiedDocumentSequence,
            openNotifiedContextBindingGeneration: state.openNotifiedContextBindingGeneration,
            openNotifiedContextReadiness: state.openNotifiedContextReadiness
        )
    }

    func committedMainDocumentURLForCurrentPage() -> URL? {
        state.committedMainDocumentURL
    }

    func hasCommittedDocumentBinding() -> Bool {
        state.documentSequence > 0
    }

    func hasDocumentBindingForLifecycleRebind() -> Bool {
        state.openNotifiedDocumentSequence != nil || state.documentSequence > 0
    }

    func shouldSkipPreCommitRebindForInitialDocument() -> Bool {
        state.documentSequence == 0
            && state.openNotifiedDocumentSequence == 0
            && state.openNotifiedContextReadiness == .loaded
    }

    func recordReportedURLIfChanged(_ resolvedURL: URL?) -> Bool {
        guard resolvedURL?.absoluteString != state.lastReportedURL?.absoluteString else {
            return false
        }
        invalidatePreparedWindowPrepublication()
        state.lastReportedURL = resolvedURL
        return true
    }

    func recordReportedLoadingCompleteIfChanged(_ isLoadingComplete: Bool) -> Bool {
        guard !state.lastReportedLoading.matches(isLoadingComplete) else {
            return false
        }
        invalidatePreparedWindowPrepublication()
        state.lastReportedLoading = .reported(isLoadingComplete)
        return true
    }

    func recordReportedTitleIfChanged(_ title: String?) -> Bool {
        guard state.lastReportedTitle != title else {
            return false
        }
        invalidatePreparedWindowPrepublication()
        state.lastReportedTitle = title
        return true
    }

    func noteCommittedMainDocumentNavigation(to url: URL) {
        invalidatePreparedWindowPrepublication()
        state.documentSequence &+= 1
        state.committedMainDocumentURL = url
    }

    func resetDocumentBindingForContentScriptRebind() {
        invalidatePreparedWindowPrepublication()
        state.documentSequence = 0
        state.committedMainDocumentURL = nil
        clearOpenNotificationDocumentBinding()
    }

    func invalidatePageForWebViewReplacement() {
        invalidatePreparedWindowPrepublication()
        state.documentSequence &+= 1
    }

    func noteOpenNotification(
        extensionContextBindingGeneration: UInt64?,
        contextReadiness: TabExtensionContextReadiness
    ) {
        if state.preparedWindowPrepublicationToken?.phase == .prepared {
            advanceMutationRevision()
        } else if state.awaitingSupersedingOpenToken != nil {
            advanceMutationRevision()
        } else {
            invalidatePreparedWindowPrepublication()
        }
        state.openNotifiedDocumentSequence = state.documentSequence
        state.openNotifiedContextBindingGeneration = extensionContextBindingGeneration
        state.openNotifiedContextReadiness = contextReadiness
    }

    func hasOpenNotificationForCurrentDocumentWithLoadedContexts(
        generation: ExtensionTabPublicationRevision
    ) -> Bool {
        state.didReportOpenForGeneration == generation
            && state.openNotifiedDocumentSequence == state.documentSequence
            && state.openNotifiedContextReadiness == .loaded
    }

    @discardableResult
    func markDidOpenTab(
        generation: ExtensionTabPublicationRevision,
        publisher: AnyObject? = nil,
        adapter: AnyObject? = nil
    ) -> Bool {
        guard state.acceptsFutureOpenPublications,
              state.openPublicationClaim == nil,
              state.didReportOpenForGeneration == nil
        else {
            return false
        }
        let supersededPreparation = state.preparedWindowPrepublicationToken
        let supersededCommitted = state.awaitingSupersedingOpenToken
        state.preparedWindowPrepublicationToken = nil
        state.committedWindowPrepublicationTokenIdentity = nil
        state.committedWindowPrepublicationToken = nil
        let claim = makeOpenPublicationClaim(
            generation: generation,
            publisher: publisher,
            adapter: adapter
        )
        state.openPublicationClaim = claim
        state.settledOpenPublicationClaimIdentity = nil
        state.didReportOpenForGeneration = generation
        advanceMutationRevision()

        let handoffToken = supersededPreparation ?? supersededCommitted
        for token in [handoffToken].compactMap({ $0 })
            where token.phase == .prepared
                || token.phase == .awaitingSupersedingOpen {
            token.phase = .supersededByOpen
            token.supersedingOpenPublicationClaimIdentity =
                ObjectIdentifier(claim)
        }
        state.awaitingSupersedingOpenToken = handoffToken
        return true
    }

    @discardableResult
    func markDidOpenTab(
        generation: ExtensionTabPublicationRevision,
        committedWindowPrepublication token:
            TabExtensionPrepublicationToken,
        publisher: AnyObject? = nil,
        adapter: AnyObject? = nil
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              state.acceptsFutureOpenPublications,
              token.phase == .committed,
              token.generation == generation,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              state.openPublicationClaim == nil,
              state.didReportOpenForGeneration == nil,
              state.controllerGeneration == generation,
              state.eligibleGeneration == generation
        else {
            return false
        }
        let claim = makeOpenPublicationClaim(
            generation: generation,
            publisher: publisher,
            adapter: adapter
        )
        state.openPublicationClaim = claim
        state.settledOpenPublicationClaimIdentity = nil
        state.didReportOpenForGeneration = generation
        advanceMutationRevision()
        token.openPublicationClaimIdentity = ObjectIdentifier(claim)
        token.committedMutationRevision = state.mutationRevision
        return true
    }

    func reserveDidOpenTab(
        generation: ExtensionTabPublicationRevision,
        publisher: AnyObject? = nil,
        adapter: AnyObject? = nil
    ) -> TabExtensionOpenPublicationClaim? {
        guard markDidOpenTab(
            generation: generation,
            publisher: publisher,
            adapter: adapter
        ) else {
            return nil
        }
        return currentOpenPublicationClaim(generation: generation)
    }

    func reserveDidOpenTab(
        generation: ExtensionTabPublicationRevision,
        committedWindowPrepublication token:
            TabExtensionPrepublicationToken,
        publisher: AnyObject? = nil,
        adapter: AnyObject? = nil
    ) -> TabExtensionOpenPublicationClaim? {
        guard markDidOpenTab(
            generation: generation,
            committedWindowPrepublication: token,
            publisher: publisher,
            adapter: adapter
        ) else {
            return nil
        }
        return currentOpenPublicationClaim(generation: generation)
    }

    func pageIdentity(tabId: UUID) -> TabExtensionPageIdentity {
        let tabIdString = tabId.uuidString.lowercased()
        let pageGeneration = String(state.documentSequence)
        return TabExtensionPageIdentity(
            tabId: tabIdString,
            pageGeneration: pageGeneration,
            pageId: "\(tabIdString):\(pageGeneration)"
        )
    }

    func isCurrentPage(
        tabId: UUID,
        pageId: String,
        pageGeneration: String
    ) -> Bool {
        let identity = pageIdentity(tabId: tabId)
        return identity.pageId == pageId
            && identity.pageGeneration == pageGeneration
    }

    private func clearOpenNotificationDocumentBinding() {
        state.openNotifiedDocumentSequence = nil
        state.openNotifiedContextBindingGeneration = nil
        state.openNotifiedContextReadiness = .notNotified
    }

    private func invalidatePreparedWindowPrepublication() {
        state.preparedWindowPrepublicationToken?.phase = .finished
        state.preparedWindowPrepublicationToken = nil
        state.awaitingSupersedingOpenToken?.phase = .finished
        state.awaitingSupersedingOpenToken = nil
        advanceMutationRevision()
    }

    private func advanceMutationRevision() {
        state.mutationRevision &+= 1
    }

    private func makeOpenPublicationClaim(
        generation: ExtensionTabPublicationRevision,
        publisher: AnyObject?,
        adapter: AnyObject?
    ) -> TabExtensionOpenPublicationClaim {
        TabExtensionOpenPublicationClaim(
            sourceIdentity: ObjectIdentifier(self),
            generation: generation,
            publisher: publisher,
            adapter: adapter
        )
    }

    private func windowPrepublicationSnapshot()
        -> TabExtensionPrepublicationSnapshot {
        TabExtensionPrepublicationSnapshot(
            controllerGeneration: state.controllerGeneration,
            documentSequence: state.documentSequence,
            committedMainDocumentURL: state.committedMainDocumentURL,
            openNotifiedDocumentSequence: state.openNotifiedDocumentSequence,
            openNotifiedContextBindingGeneration:
                state.openNotifiedContextBindingGeneration,
            openNotifiedContextReadiness:
                state.openNotifiedContextReadiness,
            lastReportedURL: state.lastReportedURL,
            lastReportedLoading: state.lastReportedLoading,
            lastReportedTitle: state.lastReportedTitle,
            didReportOpenForGeneration: state.didReportOpenForGeneration,
            eligibleGeneration: state.eligibleGeneration,
            committedWindowPrepublicationTokenIdentity:
                state.committedWindowPrepublicationTokenIdentity,
            committedWindowPrepublicationToken:
                state.committedWindowPrepublicationToken,
            openPublicationClaim: state.openPublicationClaim,
            settledOpenPublicationClaimIdentity:
                state.settledOpenPublicationClaimIdentity
        )
    }
}
