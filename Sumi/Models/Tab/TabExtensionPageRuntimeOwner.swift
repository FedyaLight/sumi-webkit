import Foundation

@MainActor
final class TabExtensionRuntimeState {
    var controllerGeneration: UInt64 = 0
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
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
    var committedWindowPrepublicationTokenIdentity: ObjectIdentifier?
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
    let controllerGeneration: UInt64
    let documentSequence: UInt64
    let committedMainDocumentURL: URL?
    let openNotifiedDocumentSequence: UInt64?
    let openNotifiedContextBindingGeneration: UInt64?
    let openNotifiedContextReadiness: TabExtensionContextReadiness
    let lastReportedURL: URL?
    let lastReportedLoading: TabExtensionLoadingReport
    let lastReportedTitle: String?
    let didReportOpenForGeneration: UInt64
    let eligibleGeneration: UInt64
    let committedWindowPrepublicationTokenIdentity: ObjectIdentifier?
}

fileprivate enum TabExtensionPrepublicationPhase: Equatable {
    case prepared
    case committed
    case finished
}

/// Opaque, single-use rollback token for extension state prepared before a
/// browser window crosses its publication boundary.
@MainActor
final class TabExtensionPrepublicationToken {
    fileprivate let sourceIdentity: ObjectIdentifier
    fileprivate let generation: UInt64
    fileprivate let snapshot: TabExtensionPrepublicationSnapshot
    fileprivate var phase = TabExtensionPrepublicationPhase.prepared

    fileprivate init(
        sourceIdentity: ObjectIdentifier,
        generation: UInt64,
        snapshot: TabExtensionPrepublicationSnapshot
    ) {
        self.sourceIdentity = sourceIdentity
        self.generation = generation
        self.snapshot = snapshot
    }
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
        get { state.didReportOpenForGeneration != 0 }
        set {
            guard newValue == false else { return }
            clearOpenNotificationGeneration()
        }
    }

    var lastOpenNotificationGeneration: UInt64 {
        get { state.didReportOpenForGeneration }
        set { state.didReportOpenForGeneration = newValue }
    }

    var controllerGeneration: UInt64 {
        get { state.controllerGeneration }
        set { state.controllerGeneration = newValue }
    }

    var documentSequence: UInt64 {
        get { state.documentSequence }
        set { state.documentSequence = newValue }
    }

    var committedMainDocumentURL: URL? {
        get { state.committedMainDocumentURL }
        set { state.committedMainDocumentURL = newValue }
    }

    var openNotifiedDocumentSequence: UInt64? {
        get { state.openNotifiedDocumentSequence }
        set { state.openNotifiedDocumentSequence = newValue }
    }

    var openNotifiedContextBindingGeneration: UInt64? {
        get { state.openNotifiedContextBindingGeneration }
        set { state.openNotifiedContextBindingGeneration = newValue }
    }

    var openNotifiedContextReadiness: TabExtensionContextReadiness {
        get { state.openNotifiedContextReadiness }
        set { state.openNotifiedContextReadiness = newValue }
    }

    var lastReportedURL: URL? {
        get { state.lastReportedURL }
        set { state.lastReportedURL = newValue }
    }

    var hasReportedLoadingComplete: Bool {
        state.lastReportedLoading.hasReported
    }

    var lastReportedTitle: String? {
        get { state.lastReportedTitle }
        set { state.lastReportedTitle = newValue }
    }

    var eligibleGeneration: UInt64 {
        get { state.eligibleGeneration }
        set { state.eligibleGeneration = newValue }
    }

    func clearOpenNotificationGeneration() {
        state.didReportOpenForGeneration = 0
        state.committedWindowPrepublicationTokenIdentity = nil
    }

    func prepareGeneration(_ generation: UInt64) {
        guard state.controllerGeneration != generation else { return }
        state.controllerGeneration = generation
        state.lastReportedURL = nil
        state.lastReportedLoading = .notReported
        state.lastReportedTitle = nil
        state.didReportOpenForGeneration = 0
        state.eligibleGeneration = 0
        clearOpenNotificationDocumentBinding()
    }

    func markEligible(for generation: UInt64) {
        state.eligibleGeneration = generation
    }

    /// Makes a new Tab queryable by extension window adapters without emitting
    /// `didOpenTab`. The returned token must be committed after window
    /// publication or rolled back if the window transaction is rejected.
    func prepareForWindowPrepublication(
        generation: UInt64
    ) -> TabExtensionPrepublicationToken {
        let token = TabExtensionPrepublicationToken(
            sourceIdentity: ObjectIdentifier(self),
            generation: generation,
            snapshot: TabExtensionPrepublicationSnapshot(
                controllerGeneration: state.controllerGeneration,
                documentSequence: state.documentSequence,
                committedMainDocumentURL: state.committedMainDocumentURL,
                openNotifiedDocumentSequence:
                    state.openNotifiedDocumentSequence,
                openNotifiedContextBindingGeneration:
                    state.openNotifiedContextBindingGeneration,
                openNotifiedContextReadiness:
                    state.openNotifiedContextReadiness,
                lastReportedURL: state.lastReportedURL,
                lastReportedLoading: state.lastReportedLoading,
                lastReportedTitle: state.lastReportedTitle,
                didReportOpenForGeneration:
                    state.didReportOpenForGeneration,
                eligibleGeneration: state.eligibleGeneration,
                committedWindowPrepublicationTokenIdentity:
                    state.committedWindowPrepublicationTokenIdentity
            )
        )
        prepareGeneration(generation)
        markEligible(for: generation)
        return token
    }

    @discardableResult
    func commitWindowPrepublication(
        _ token: TabExtensionPrepublicationToken,
        willEmitOpen: Bool
    ) -> Bool {
        guard canCommitWindowPrepublication(token) else { return false }
        if willEmitOpen {
            token.phase = .committed
            state.committedWindowPrepublicationTokenIdentity =
                ObjectIdentifier(token)
        } else {
            token.phase = .finished
        }
        return true
    }

    func canCommitWindowPrepublication(
        _ token: TabExtensionPrepublicationToken
    ) -> Bool {
        token.sourceIdentity == ObjectIdentifier(self)
            && token.phase == .prepared
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
              state.controllerGeneration == token.generation,
              state.eligibleGeneration == token.generation
        else {
            return false
        }

        restoreWindowPrepublicationSnapshot(token.snapshot)
        token.phase = .finished
        return true
    }

    /// Reverses only the exact initial-Tab open emitted after a committed
    /// window prepublication token. A newer generation or a second publisher
    /// makes the token stale instead of allowing it to erase newer state.
    @discardableResult
    func revokeCommittedWindowPrepublication(
        _ token: TabExtensionPrepublicationToken,
        openGeneration: UInt64
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .committed,
              token.generation == openGeneration,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              state.controllerGeneration == openGeneration,
              state.eligibleGeneration == openGeneration,
              state.didReportOpenForGeneration == openGeneration
        else {
            return false
        }

        restoreWindowPrepublicationSnapshot(token.snapshot)
        token.phase = .finished
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
    }

    func isEligible(for generation: UInt64) -> Bool {
        state.eligibleGeneration == generation
    }

    func hasDidOpenTabNotification(for generation: UInt64) -> Bool {
        state.didReportOpenForGeneration == generation
    }

    /// Atomically tombstones one exact generation before crossing WebKit's
    /// synchronous `didCloseTab` boundary. A nested reload or teardown sees
    /// the tombstone and cannot balance the same open twice.
    @discardableResult
    func claimDidOpenTabNotificationForClose(
        generation: UInt64
    ) -> Bool {
        guard state.didReportOpenForGeneration == generation else {
            return false
        }
        state.didReportOpenForGeneration = 0
        state.committedWindowPrepublicationTokenIdentity = nil
        return true
    }

    func hasAnyDidOpenTabNotification() -> Bool {
        state.didReportOpenForGeneration > 0
    }

    func currentOpenNotificationGeneration() -> UInt64 {
        state.didReportOpenForGeneration
    }

    func currentEligibleGeneration() -> UInt64 {
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
        state.lastReportedURL = resolvedURL
        return true
    }

    func recordReportedLoadingCompleteIfChanged(_ isLoadingComplete: Bool) -> Bool {
        guard !state.lastReportedLoading.matches(isLoadingComplete) else {
            return false
        }
        state.lastReportedLoading = .reported(isLoadingComplete)
        return true
    }

    func recordReportedTitleIfChanged(_ title: String?) -> Bool {
        guard state.lastReportedTitle != title else {
            return false
        }
        state.lastReportedTitle = title
        return true
    }

    func noteCommittedMainDocumentNavigation(to url: URL) {
        state.documentSequence &+= 1
        state.committedMainDocumentURL = url
    }

    func resetDocumentBindingForContentScriptRebind() {
        state.documentSequence = 0
        state.committedMainDocumentURL = nil
        clearOpenNotificationDocumentBinding()
    }

    func invalidatePageForWebViewReplacement() {
        state.documentSequence &+= 1
    }

    func noteOpenNotification(
        extensionContextBindingGeneration: UInt64?,
        contextReadiness: TabExtensionContextReadiness
    ) {
        state.openNotifiedDocumentSequence = state.documentSequence
        state.openNotifiedContextBindingGeneration = extensionContextBindingGeneration
        state.openNotifiedContextReadiness = contextReadiness
    }

    func hasOpenNotificationForCurrentDocumentWithLoadedContexts(
        generation: UInt64
    ) -> Bool {
        state.didReportOpenForGeneration == generation
            && state.openNotifiedDocumentSequence == state.documentSequence
            && state.openNotifiedContextReadiness == .loaded
    }

    func markDidOpenTab(generation: UInt64) {
        state.committedWindowPrepublicationTokenIdentity = nil
        state.didReportOpenForGeneration = generation
    }

    @discardableResult
    func markDidOpenTab(
        generation: UInt64,
        committedWindowPrepublication token:
            TabExtensionPrepublicationToken
    ) -> Bool {
        guard token.sourceIdentity == ObjectIdentifier(self),
              token.phase == .committed,
              token.generation == generation,
              state.committedWindowPrepublicationTokenIdentity
                == ObjectIdentifier(token),
              state.controllerGeneration == generation,
              state.eligibleGeneration == generation
        else {
            return false
        }
        state.didReportOpenForGeneration = generation
        return true
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
}
