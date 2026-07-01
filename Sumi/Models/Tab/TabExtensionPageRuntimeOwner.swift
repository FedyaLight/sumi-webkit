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
    var lastReportedLoading: TabExtensionLoadingReport = .notReported
    var lastReportedTitle: String?
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
}

enum TabExtensionContextReadiness: Equatable, Sendable {
    case notNotified
    case unknown
    case loaded
    case missing
}

private enum TabExtensionLoadingReport: Equatable {
    case notReported
    case reported(Bool)

    var hasReported: Bool {
        self != .notReported
    }

    func matches(_ isLoadingComplete: Bool) -> Bool {
        self == .reported(isLoadingComplete)
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

    func isEligible(for generation: UInt64) -> Bool {
        state.eligibleGeneration == generation
    }

    func hasDidOpenTabNotification(for generation: UInt64) -> Bool {
        state.didReportOpenForGeneration == generation
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
        state.didReportOpenForGeneration = generation
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
