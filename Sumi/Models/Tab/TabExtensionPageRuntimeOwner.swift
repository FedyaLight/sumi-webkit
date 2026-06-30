import Foundation

@MainActor
final class TabExtensionRuntimeState {
    var controllerGeneration: UInt64 = 0
    var documentSequence: UInt64 = 0
    var committedMainDocumentURL: URL?
    /// Document sequence when `didOpenTab` last succeeded; `nil` if never notified.
    var openNotifiedDocumentSequence: UInt64?
    /// Profile extension-context binding generation observed at the last pre-commit `didOpenTab`.
    var openNotifiedExtensionContextBindingGeneration: UInt64?
    /// Whether every enabled content-script extension context was loaded when `didOpenTab` last ran.
    var openNotifiedWithLoadedContexts: Bool?
    var lastReportedURL: URL?
    var lastReportedLoadingComplete: Bool?
    var lastReportedTitle: String?
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
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
    let openNotifiedExtensionContextBindingGeneration: UInt64?
    let openNotifiedWithLoadedContexts: Bool?
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

    var openNotifiedExtensionContextBindingGeneration: UInt64? {
        get { state.openNotifiedExtensionContextBindingGeneration }
        set { state.openNotifiedExtensionContextBindingGeneration = newValue }
    }

    var openNotifiedWithLoadedContexts: Bool? {
        get { state.openNotifiedWithLoadedContexts }
        set { state.openNotifiedWithLoadedContexts = newValue }
    }

    var lastReportedURL: URL? {
        get { state.lastReportedURL }
        set { state.lastReportedURL = newValue }
    }

    var lastReportedLoadingComplete: Bool? {
        get { state.lastReportedLoadingComplete }
        set { state.lastReportedLoadingComplete = newValue }
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
        state.lastReportedLoadingComplete = nil
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
            openNotifiedExtensionContextBindingGeneration: state.openNotifiedExtensionContextBindingGeneration,
            openNotifiedWithLoadedContexts: state.openNotifiedWithLoadedContexts
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
            && state.openNotifiedWithLoadedContexts == true
    }

    func recordReportedURLIfChanged(_ resolvedURL: URL?) -> Bool {
        guard resolvedURL?.absoluteString != state.lastReportedURL?.absoluteString else {
            return false
        }
        state.lastReportedURL = resolvedURL
        return true
    }

    func recordReportedLoadingCompleteIfChanged(_ isLoadingComplete: Bool) -> Bool {
        guard state.lastReportedLoadingComplete != isLoadingComplete else {
            return false
        }
        state.lastReportedLoadingComplete = isLoadingComplete
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

    func invalidateCurrentPageForWebViewReplacement() {
        state.documentSequence &+= 1
    }

    func noteOpenNotification(
        extensionContextBindingGeneration: UInt64?,
        loadedContexts: Bool?
    ) {
        state.openNotifiedDocumentSequence = state.documentSequence
        state.openNotifiedExtensionContextBindingGeneration = extensionContextBindingGeneration
        state.openNotifiedWithLoadedContexts = loadedContexts
    }

    func hasOpenNotificationForCurrentDocumentWithLoadedContexts(
        generation: UInt64
    ) -> Bool {
        state.didReportOpenForGeneration == generation
            && state.openNotifiedDocumentSequence == state.documentSequence
            && state.openNotifiedWithLoadedContexts == true
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
        state.openNotifiedExtensionContextBindingGeneration = nil
        state.openNotifiedWithLoadedContexts = nil
    }
}
