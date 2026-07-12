import Foundation
import WebKit

/// Commits a WebView into a tab's detached residence. This transaction owns
/// exact candidate disposition when placement or replacement cannot commit.
@MainActor
final class UntrackedWebViewInstallationService: UntrackedWebViewInstalling {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let placement: CanonicalWebViewPlacementService
    private let detachedReplacement: DetachedWebViewReplacementService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        placement: CanonicalWebViewPlacementService,
        detachedReplacement: DetachedWebViewReplacementService
    ) {
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.placement = placement
        self.detachedReplacement = detachedReplacement
    }

    @discardableResult
    func installUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> UntrackedWebViewInstallationOutcome {
        let candidateWasCanonical = tab.webViewSession.owns(webView)
        guard runtimeTabs.bind(tab).isAccepted else {
            return .rejected(
                .runtimeTabIdentityConflict,
                webViewDisposition: candidateWasCanonical
                    ? .remainsCanonical
                    : .callerMustDestroy
            )
        }
        guard query.windowIDs(for: tab.id).isEmpty else {
            return .rejected(
                .trackedResidenceExists,
                webViewDisposition: candidateWasCanonical
                    ? .remainsCanonical
                    : .callerMustDestroy
            )
        }
        if tab.webViewSession.untrackedWebView === webView {
            return .unchanged
        }
        if candidateWasCanonical {
            let outcome = placeUntracked(webView, for: tab)
            return installationOutcome(
                outcome,
                rejectedDisposition: .remainsCanonical
            )
        }
        if let displaced = tab.webViewSession.untrackedWebView
            ?? tab.webViewSession.parkedWebView {
            switch detachedReplacement.replace(
                displaced,
                with: webView,
                for: tab
            ) {
            case .committed:
                return .committed
            case .rejected:
                return .rejected(
                    .detachedReplacementRejected,
                    webViewDisposition: .callerMustDestroy
                )
            case .consumedByFailedTransaction:
                return .consumedByFailedReplacement
            }
        }
        return installationOutcome(
            placeUntracked(webView, for: tab),
            rejectedDisposition: .callerMustDestroy
        )
    }

    private func placeUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> CanonicalWebViewPlacementOutcome {
        if webView.configuration.sumiIsNormalTabWebViewConfiguration {
            return placement.placeNormalUntracked(webView, for: tab)
        }
        return placement.placeAuxiliaryUntracked(webView, for: tab)
    }

    private func installationOutcome(
        _ outcome: CanonicalWebViewPlacementOutcome,
        rejectedDisposition: RejectedWebViewDisposition
    ) -> UntrackedWebViewInstallationOutcome {
        switch outcome {
        case .committed:
            return .committed
        case .unchanged:
            return .unchanged
        case .rejected(let rejection):
            return .rejected(
                .canonicalPlacement(rejection),
                webViewDisposition: rejectedDisposition
            )
        }
    }
}
