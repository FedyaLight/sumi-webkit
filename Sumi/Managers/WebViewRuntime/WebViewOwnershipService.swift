import Foundation
import SumiWebRuntime
import WebKit

/// High-level materialization, replacement, deferral, and release facade.
/// Canonical placement is owned by `CanonicalWebViewPlacementService`; whole-
/// session replacement is owned by `DetachedWebViewReplacementService` and the
/// shared pipeline.
@MainActor
final class WebViewOwnershipService:
    AuxiliaryTrackedWebViewPlacing
{
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let placement: CanonicalWebViewPlacementService
    private let materialization: TabWebViewMaterializationService
    private let detachedReplacement: DetachedWebViewReplacementService
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let detachedCleanup: DetachedWebViewCleanupService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        placement: CanonicalWebViewPlacementService,
        materialization: TabWebViewMaterializationService,
        detachedReplacement: DetachedWebViewReplacementService,
        websiteDataCleanup: WebsiteDataCleanupService,
        detachedCleanup: DetachedWebViewCleanupService
    ) {
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.placement = placement
        self.materialization = materialization
        self.detachedReplacement = detachedReplacement
        self.websiteDataCleanup = websiteDataCleanup
        self.detachedCleanup = detachedCleanup
    }

    @discardableResult
    func registerAuxiliaryTrackedWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID
    ) -> CanonicalWebViewPlacementOutcome {
        runtimeTabs.bind(tab)
        return placement.placeAuxiliaryTracked(
            webView,
            for: tab,
            in: windowID,
            promoteToPrimary: false
        )
    }

    func webView(for tab: Tab, in windowID: UUID) -> WKWebView? {
        runtimeTabs.bind(tab)
        if query.webView(for: tab.id, in: windowID) == nil,
           deferTrackedAdmissionIfNeeded(tab: tab, windowID: windowID) {
            return nil
        }
        return materialization.webView(for: tab, in: windowID)
    }

    @discardableResult
    func assign(_ webView: WKWebView, to tab: Tab, in windowID: UUID) -> Bool {
        runtimeTabs.bind(tab)
        if query.webView(for: tab.id, in: windowID) !== webView,
           deferTrackedAdmissionIfNeeded(
                tab: tab,
                windowID: windowID,
                replay: { [weak self, weak tab, webView] in
                    guard let self, let tab else { return }
                    _ = self.assign(webView, to: tab, in: windowID)
                }
           ) {
            return false
        }

        let outcome: CanonicalWebViewPlacementOutcome
        if webView.configuration.sumiIsNormalTabWebViewConfiguration {
            outcome = placement.placeNormalTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
        } else {
            outcome = placement.placeAuxiliaryTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
        }
        guard outcome.isAccepted else {
            RuntimeDiagnostics.emit(
                "[WebViewOwnership] Rejected canonical tracked placement for tab \(tab.id): \(outcome)."
            )
            return false
        }
        tab.prepareAssignedWebView(webView)
        return true
    }

    /// Replaces the complete detached generation through the same transaction
    /// and settlement pipeline used by tracked rebuilds and profile changes.
    @discardableResult
    func replaceDetached(
        _ previous: WKWebView,
        with replacement: WKWebView,
        for tab: Tab
    ) -> WebViewDetachedReplacementCommitOutcome {
        runtimeTabs.bind(tab)
        return detachedReplacement.replace(
            previous,
            with: replacement,
            for: tab
        )
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
        let semanticRevision = tab.mainFrameLoads.currentIntent.revision
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
        detachedCleanup.releaseUntracked(for: tab)
    }

    @discardableResult
    func releaseParked(
        _ webView: WKWebView,
        for tab: Tab,
        reason: String
    ) -> Bool {
        runtimeTabs.bind(tab)
        return detachedCleanup.releaseParked(
            webView,
            for: tab,
            reason: reason
        )
    }

    /// Creates an extension-ready candidate without runtime side effects,
    /// commits its canonical residence, then prepares only the committed view.
    @discardableResult
    func replaceLiveWebView(
        for tab: Tab,
        in windowID: UUID?,
        reason: String,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)? = nil,
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
                            prepareCandidateConfiguration: prepareCandidateConfiguration,
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
            prepareCandidateConfiguration: prepareCandidateConfiguration
        ) else {
            return nil
        }
        if let validate, validate(replacement) == false {
            tab.cleanupCloneWebView(replacement)
            return nil
        }

        if let windowID {
            guard assign(replacement, to: tab, in: windowID) else {
                tab.cleanupCloneWebView(replacement)
                return nil
            }
        } else {
            if let displaced = tab.webViewSession.untrackedWebView
                ?? tab.webViewSession.parkedWebView,
               displaced !== replacement {
                switch detachedReplacement.replace(
                    displaced,
                    with: replacement,
                    for: tab
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
                let outcome = placement.placeNormalUntracked(
                    replacement,
                    for: tab
                )
                guard outcome.isAccepted else {
                    tab.cleanupCloneWebView(replacement)
                    return nil
                }
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
        let semanticRevision = tab.mainFrameLoads.currentIntent.revision
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

}
