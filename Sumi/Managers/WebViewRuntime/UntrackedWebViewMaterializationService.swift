import WebKit

enum UntrackedWebViewMaterializationOutcome {
    case available(WKWebView)
    case deferred
    case failed
}

/// Resolves or creates the detached normal WebView used by Glance and other
/// untracked tab lifetimes. Canonical installation remains a separate service.
@MainActor
final class UntrackedWebViewMaterializationService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let websiteDataCleanup: WebsiteDataCleanupService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        websiteDataCleanup: WebsiteDataCleanupService
    ) {
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.websiteDataCleanup = websiteDataCleanup
    }

    func webView(for tab: Tab) -> WKWebView? {
        guard case .available(let webView) = materialize(for: tab) else {
            return nil
        }
        return webView
    }

    func materialize(
        for tab: Tab
    ) -> UntrackedWebViewMaterializationOutcome {
        guard runtimeTabs.bind(tab).isAccepted else { return .failed }
        if let existing = query.anyLiveWebView(for: tab) {
            return .available(existing)
        }
        if websiteDataCleanup.deferWebViewMaterialization(
            for: tab,
            replay: { [weak self, weak tab] in
                guard let self, let tab else { return }
                _ = materialize(for: tab)
            }
        ) {
            return .deferred
        }

        switch tab.ensureUntrackedNormalWebViewOutcome(
            reason: "UntrackedWebViewMaterializationService.materialize"
        ) {
        case .available(let webView), .superseded(let webView):
            return .available(webView)
        case .deferred:
            return .deferred
        case .failed:
            return .failed
        }
    }
}
