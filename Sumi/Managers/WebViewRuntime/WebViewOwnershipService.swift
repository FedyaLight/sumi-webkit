import Foundation
import SumiWebRuntime
import WebKit

enum WebViewDetachedReplacementCommitOutcome: Equatable {
    /// The replacement generation is canonical and the retired generation was
    /// handed to the shared replacement pipeline for physical cleanup.
    case committed
    /// Admission never began; the caller still owns the replacement WebView.
    case rejected
    /// Admission began but settlement failed. The pipeline owns cleanup of the
    /// replacement generation, so the caller must not destroy it again.
    case consumedByFailedTransaction
}

enum UntrackedWebViewMaterializationOutcome {
    case available(WKWebView)
    case deferred
    case failed
}

/// The only app-level writer for canonical WebView ownership.
///
/// Reads stay in `WebViewOwnershipQuery`; whole-session replacement settlement
/// stays in `WebViewReplacementPipeline`. This service owns the mutation rules
/// that join a concrete Tab to those two boundaries.
@MainActor
final class WebViewOwnershipService {
    private let webViewSessions: WebViewSessionRepository
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let trackedRegistration: WebViewTrackedRegistrationOwner
    private let materialization: TabWebViewMaterializationService
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let processRecovery: WebContentProcessRecoveryService
    private let mediaProtection: WebViewMediaProtectionOwner
    private let protectedCommands: WebViewProtectedCommandDispatchOwner
    private let replacementPipeline: WebViewReplacementPipeline

    init(
        webViewSessions: WebViewSessionRepository,
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        trackedRegistration: WebViewTrackedRegistrationOwner,
        materialization: TabWebViewMaterializationService,
        websiteDataCleanup: WebsiteDataCleanupService,
        processRecovery: WebContentProcessRecoveryService,
        mediaProtection: WebViewMediaProtectionOwner,
        protectedCommands: WebViewProtectedCommandDispatchOwner,
        replacementPipeline: WebViewReplacementPipeline
    ) {
        self.webViewSessions = webViewSessions
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.trackedRegistration = trackedRegistration
        self.materialization = materialization
        self.websiteDataCleanup = websiteDataCleanup
        self.processRecovery = processRecovery
        self.mediaProtection = mediaProtection
        self.protectedCommands = protectedCommands
        self.replacementPipeline = replacementPipeline
    }

    func registerTrackedWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID
    ) {
        runtimeTabs.bind(tab)
        trackedRegistration.register(webView, for: tab.id, in: windowID)
    }

    func webView(for tab: Tab, in windowID: UUID) -> WKWebView? {
        runtimeTabs.bind(tab)
        if query.webView(for: tab.id, in: windowID) == nil,
           deferTrackedAdmissionIfNeeded(tab: tab, windowID: windowID) {
            return nil
        }
        return materialization.webView(for: tab, in: windowID)
    }

    func assign(_ webView: WKWebView, to tab: Tab, in windowID: UUID) {
        runtimeTabs.bind(tab)
        if query.webView(for: tab.id, in: windowID) !== webView,
           deferTrackedAdmissionIfNeeded(
                tab: tab,
                windowID: windowID,
                replay: { [weak self, weak tab, webView] in
                    guard let self, let tab else { return }
                    self.assign(webView, to: tab, in: windowID)
                }
           ) {
            return
        }

        registerTrackedWebView(webView, for: tab, in: windowID)
        precondition(
            trackedRegistration.promotePrimary(
                webView,
                owner: .init(tabID: tab.id, windowID: windowID)
            ),
            "Assigned WebView was not registered"
        )
        tab.prepareAssignedWebView(webView)
    }

    func installUntracked(_ webView: WKWebView, for tab: Tab) {
        runtimeTabs.bind(tab)
        precondition(
            query.windowIDs(for: tab.id).isEmpty,
            "An untracked WebView cannot be installed for a window-tracked tab"
        )
        guard let displaced = tab.webViewSession.untrackedWebView,
              displaced !== webView else {
            tab.replaceUntrackedWebView(webView)
            return
        }

        precondition(
            replaceDetached(
                displaced,
                with: webView,
                for: tab,
                reason: "WebViewOwnershipService.installUntracked"
            ) == .committed,
            "Untracked WebView replacement failed its canonical transaction"
        )
    }

    /// Replaces the complete detached generation through the same transaction
    /// and settlement pipeline used by tracked rebuilds and profile changes.
    @discardableResult
    func replaceDetached(
        _ previous: WKWebView,
        with replacement: WKWebView,
        for tab: Tab,
        reason: String
    ) -> WebViewDetachedReplacementCommitOutcome {
        runtimeTabs.bind(tab)
        let snapshot = webViewSessions.snapshot(for: tab.id)
        guard snapshot.windowWebViews.isEmpty else { return .rejected }

        let residence: WebViewDetachedReplacementResidence
        if snapshot.untrackedWebView === previous {
            residence = .untracked
        } else if snapshot.parkedWebView === previous,
                  snapshot.untrackedWebView == nil {
            residence = .parked
        } else {
            return .rejected
        }

        let prepared = PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .detached(webView: replacement, residence: residence),
            replacements: [replacement],
            trackedReplacements: [],
            bindingReplacements: [],
            targetURL: tab.url,
            semanticRevision: tab.currentMainFrameNavigationIntent().revision,
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            requiresExtensionRuntimePreparation: false,
            previousProtectionState:
                tab.reloadPolicyStateOwner.protectionAppliedAttachmentState,
            previousSafariContentBlockerState:
                tab.reloadPolicyStateOwner
                    .safariContentBlockerAppliedAttachmentState
        )

        let start = replacementPipeline.begin(
            [prepared],
            profileIDs: Set([prepared.profileID].compactMap { $0 }),
            validateModel: {
                let current = self.webViewSessions.snapshot(for: tab.id)
                return current.generation == snapshot.generation
                    && current.windowWebViews.isEmpty
                    && (
                        residence == .untracked
                            ? current.untrackedWebView === previous
                            : current.parkedWebView === previous
                                && current.untrackedWebView == nil
                    )
            },
            modelCommit: { /* Detached replacement has no model mutation. */ },
            modelRollback: { /* Detached replacement has no model mutation. */ },
            completion: { _ in }
        )

        switch start {
        case .committed:
            return .committed
        case .stale, .conflict, .invalid, .modelCommitFailed:
            return .rejected
        case .settlementConflict, .leaseLost:
            return .consumedByFailedTransaction
        case .started:
            preconditionFailure(
                "A detached replacement without navigation bindings must settle synchronously"
            )
        }
    }

    @discardableResult
    func ensureUntracked(for tab: Tab) -> WKWebView? {
        guard case .available(let webView) = ensureUntrackedOutcome(for: tab) else {
            return nil
        }
        return webView
    }

    func ensureUntrackedOutcome(
        for tab: Tab
    ) -> UntrackedWebViewMaterializationOutcome {
        runtimeTabs.bind(tab)
        if let existing = query.anyLiveWebView(for: tab) {
            return .available(existing)
        }
        let semanticRevision = tab.currentMainFrameNavigationIntent().revision
        if websiteDataCleanup.permitsInternalSubmission(
            tabID: tab.id,
            semanticRevision: semanticRevision
        ) == false,
        websiteDataCleanup.deferOrdinaryAdmission(
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            key: .webViewMaterialization(tabID: tab.id),
            replay: { [weak self, weak tab] in
                guard let self, let tab else { return }
                _ = self.ensureUntrackedOutcome(for: tab)
            }
        ) {
            return .deferred
        }

        switch tab.ensureUntrackedNormalWebViewOutcome(
            reason: "WebViewOwnershipService.ensureUntracked"
        ) {
        case .available(let webView):
            return .available(webView)
        case .deferred:
            return .deferred
        case .failed:
            return .failed
        }
    }

    func releaseUntracked(for tab: Tab) {
        runtimeTabs.bind(tab)
        guard let webView = tab.webViewSession.untrackedWebView else { return }
        guard let lease = webViewSessions.releaseUntrackedAndBeginPendingCleanup(
            webView,
            for: tab.id
        ) else {
            preconditionFailure(
                "Untracked WebView release lost its expected repository residence"
            )
        }
        websiteDataCleanup.webViewDidLeaveRuntime(webView)
        finishPendingCleanup(
            of: webView,
            lease: lease,
            tab: tab,
            reason: "WebViewOwnershipService.releaseUntracked"
        )
    }

    @discardableResult
    func releaseParked(
        _ webView: WKWebView,
        for tab: Tab,
        reason: String
    ) -> Bool {
        runtimeTabs.bind(tab)
        guard let lease = webViewSessions.releaseParkedAndBeginPendingCleanup(
            webView,
            for: tab.id
        ) else {
            return false
        }
        websiteDataCleanup.webViewDidLeaveRuntime(webView)
        finishPendingCleanup(
            of: webView,
            lease: lease,
            tab: tab,
            reason: reason
        )
        return true
    }

    /// Creates an extension-ready candidate without runtime side effects,
    /// commits its canonical residence, then prepares only the committed view.
    @discardableResult
    func replaceLiveWebView(
        for tab: Tab,
        in windowID: UUID?,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil,
        prepareCommittedReplacement: ((WKWebView) -> Void)? = nil,
        validate: ((WKWebView) -> Bool)? = nil
    ) -> WKWebView? {
        runtimeTabs.bind(tab)
        if windowID == nil {
            precondition(
                query.windowIDs(for: tab.id).isEmpty,
                "Untracked replacement requires an untracked tab session"
            )
        } else if let windowID,
                  deferTrackedAdmissionIfNeeded(
                    tab: tab,
                    windowID: windowID,
                    replay: { [weak self, weak tab] in
                        guard let self, let tab else { return }
                        _ = self.replaceLiveWebView(
                            for: tab,
                            in: windowID,
                            reason: reason,
                            prepareConfiguration: prepareConfiguration,
                            prepareCommittedReplacement: prepareCommittedReplacement,
                            validate: validate
                        )
                    }
                  ) {
            return nil
        }

        guard let replacement = tab.makeNormalTabWebView(
            reason: reason,
            prepareExtensionRuntime: false,
            prepareConfiguration: prepareConfiguration
        ) else {
            return nil
        }
        if let validate, validate(replacement) == false {
            tab.cleanupCloneWebView(replacement)
            return nil
        }

        if let windowID {
            assign(replacement, to: tab, in: windowID)
            precondition(
                query.webView(for: tab.id, in: windowID) === replacement,
                "Tracked replacement callback requires canonical admission"
            )
        } else {
            if let displaced = tab.webViewSession.untrackedWebView,
               displaced !== replacement {
                switch replaceDetached(
                    displaced,
                    with: replacement,
                    for: tab,
                    reason: reason
                ) {
                case .committed:
                    break
                case .rejected:
                    tab.cleanupCloneWebView(replacement)
                    return nil
                case .consumedByFailedTransaction:
                    return nil
                }
            } else {
                installUntracked(replacement, for: tab)
            }
        }
        prepareCommittedReplacement?(replacement)
        return replacement
    }

    private func deferTrackedAdmissionIfNeeded(
        tab: Tab,
        windowID: UUID,
        replay: (@MainActor () -> Void)? = nil
    ) -> Bool {
        let semanticRevision = tab.currentMainFrameNavigationIntent().revision
        guard websiteDataCleanup.permitsInternalSubmission(
            tabID: tab.id,
            semanticRevision: semanticRevision
        ) == false else {
            return false
        }
        return websiteDataCleanup.deferOrdinaryAdmission(
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            key: .trackedRegistration(tabID: tab.id, windowID: windowID),
            replay: replay ?? { [weak self, weak tab] in
                guard let self, let tab else { return }
                _ = self.webView(for: tab, in: windowID)
            }
        )
    }

    private func finishPendingCleanup(
        of webView: WKWebView,
        lease: WebViewPendingCleanupLease,
        tab: Tab,
        reason: String
    ) {
        processRecovery.cancel(webView)
        if mediaProtection.isProtected(webView) {
            switch protectedCommands.schedule(
                .performFallbackWebViewCleanup(
                    webViewID: ObjectIdentifier(webView),
                    lease: lease
                ),
                for: webView,
                reason: reason
            ) {
            case .scheduled:
                return
            case .notProtected:
                break
            case .invalidTarget, .droppedAtCapacity:
                preconditionFailure(
                    "Guaranteed leased WebView cleanup could not be scheduled"
                )
            }
        }

        precondition(
            webViewSessions.consumePendingCleanup(of: webView, lease: lease),
            "Leased WebView cleanup lost its exact repository claim"
        )
        tab.cleanupCloneWebView(webView)
    }
}
