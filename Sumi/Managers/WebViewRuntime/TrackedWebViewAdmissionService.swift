import Foundation
import WebKit

enum TrackedWebViewAdmissionOutcome: Equatable {
    enum Rejection: Equatable {
        case physicalTabIdentityMismatch
        case runtimeTabIdentityConflict
    }

    case placed(CanonicalWebViewPlacementOutcome)
    /// No physical candidate is retained by the admission queue. The caller
    /// still owns it and must destroy it; replay recreates the semantic work.
    case deferred
    case rejected(Rejection)

    var isAccepted: Bool {
        guard case .placed(let placement) = self else { return false }
        return placement.isAccepted
    }
}

/// Admits one exact WebView to one tracked window residence. It owns the
/// website-data barrier and canonical placement decision, but not replacement,
/// detached residence, or physical cleanup.
@MainActor
final class TrackedWebViewAdmissionService: AuxiliaryTrackedWebViewPlacing {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let placement: CanonicalWebViewPlacementService
    private let materialization: TabWebViewMaterializationService
    private let websiteDataCleanup: WebsiteDataCleanupService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        placement: CanonicalWebViewPlacementService,
        materialization: TabWebViewMaterializationService,
        websiteDataCleanup: WebsiteDataCleanupService
    ) {
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.placement = placement
        self.materialization = materialization
        self.websiteDataCleanup = websiteDataCleanup
    }

    @discardableResult
    func registerAuxiliaryTrackedWebView(
        _ webView: FocusableWKWebView,
        for tab: Tab,
        in windowID: UUID
    ) -> TrackedWebViewAdmissionOutcome {
        guard webView.owningTab === tab else {
            return .rejected(.physicalTabIdentityMismatch)
        }
        guard runtimeTabs.bind(tab).isAccepted else {
            return .rejected(.runtimeTabIdentityConflict)
        }
        return .placed(placement.placeAuxiliaryTracked(
            webView,
            for: tab,
            in: windowID,
            promoteToPrimary: false
        ))
    }

    func webView(
        for tab: Tab,
        in windowID: UUID,
        replayMaterialization: (@MainActor () -> Void)? = nil
    ) -> WKWebView? {
        guard runtimeTabs.bind(tab).isAccepted else { return nil }
        if query.webView(for: tab.id, in: windowID) == nil,
           deferMaterializationIfNeeded(
                tab: tab,
                windowID: windowID,
                replay: replayMaterialization
           ) {
            return nil
        }
        return materialization.webView(for: tab, in: windowID)
    }

    /// Attempts only the current candidate. On deferral the caller retains and
    /// must destroy it; the supplied semantic replay creates a fresh candidate.
    @discardableResult
    func attemptAssignment(
        _ candidate: WKWebView,
        to tab: Tab,
        in windowID: UUID,
        replaySemanticOperation: @escaping @MainActor () -> Void
    ) -> TrackedWebViewAdmissionOutcome {
        guard let webView = candidate as? FocusableWKWebView,
              webView.owningTab === tab else {
            return .rejected(.physicalTabIdentityMismatch)
        }
        guard runtimeTabs.bind(tab).isAccepted else {
            return .rejected(.runtimeTabIdentityConflict)
        }
        if query.webView(for: tab.id, in: windowID) !== webView,
           websiteDataCleanup.deferTrackedWebViewReplacement(
                for: tab,
                in: windowID,
                replay: replaySemanticOperation
           ) {
            return .deferred
        }

        let outcome = webView.configuration.sumiIsNormalTabWebViewConfiguration
            ? placement.placeNormalTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
            : placement.placeAuxiliaryTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
        guard outcome.isAccepted else {
            RuntimeDiagnostics.emit(
                "[TrackedWebViewAdmission] Rejected placement for tab \(tab.id): \(outcome)."
            )
            return .placed(outcome)
        }
        tab.prepareAssignedWebView(webView)
        return .placed(outcome)
    }

    @discardableResult
    func deferMaterializationIfNeeded(
        tab: Tab,
        windowID: UUID,
        replay: (@MainActor () -> Void)? = nil
    ) -> Bool {
        websiteDataCleanup.deferTrackedWebViewAdmission(
            for: tab,
            in: windowID,
            replay: replay ?? { [weak self, weak tab] in
                guard let self, let tab else { return }
                _ = webView(for: tab, in: windowID)
            }
        )
    }
}
