import AppKit
import WebKit

struct SumiReaderNavigationPolicy {
    enum Decision: Equatable {
        case allowInitialDocument
        case routeToCanonical(URL)
        case cancel
    }

    private enum Phase {
        case awaitingInitialDocument
        case presented
        case terminated
    }

    private var phase = Phase.awaitingInitialDocument

    mutating func decide(
        navigationType: WKNavigationType,
        isMainFrame: Bool?,
        destinationURL: URL?
    ) -> Decision {
        if navigationType == .linkActivated {
            guard phase == .presented,
                  let destinationURL,
                  let scheme = destinationURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return .cancel
            }
            phase = .terminated
            return .routeToCanonical(destinationURL)
        }

        // Tab.loadURL currently preserves only the URL. Routing a form through
        // it would silently discard the HTTP method and body, so forms remain
        // fail-closed until canonical request-preserving navigation exists.
        if navigationType == .formSubmitted
            || navigationType == .formResubmitted {
            return .cancel
        }

        guard phase == .awaitingInitialDocument,
              isMainFrame == true,
              navigationType == .other else {
            return .cancel
        }
        phase = .presented
        return .allowInitialDocument
    }
}

/// View-local Reader representation. It never becomes a Tab navigation
/// participant: the canonical WebView, history, permission identity and
/// cross-window authority stay untouched underneath this ephemeral surface.
@MainActor
final class ReaderPresentationSession: NSObject, WKNavigationDelegate {
    let sourceDocumentLease: TabMainFrameDocumentLease
    let sourceURL: URL
    let webView: FocusableWKWebView

    private let navigate: (URL) -> Void
    private weak var host: SumiWebViewContainerView?
    private var navigationPolicy = SumiReaderNavigationPolicy()

    init(
        sourceDocumentLease: TabMainFrameDocumentLease,
        sourceURL: URL,
        navigate: @escaping (URL) -> Void
    ) {
        self.sourceDocumentLease = sourceDocumentLease
        self.sourceURL = sourceURL
        self.navigate = navigate

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func attach(to host: SumiWebViewContainerView) {
        self.host = host
    }

    func detach(from host: SumiWebViewContainerView) {
        guard self.host === host else { return }
        self.host = nil
    }

    func load(_ html: String) {
        webView.loadHTMLString(html, baseURL: sourceURL)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        switch navigationPolicy.decide(
            navigationType: navigationAction.navigationType,
            isMainFrame: navigationAction.targetFrame?.isMainFrame,
            destinationURL: navigationAction.request.url
        ) {
        case .allowInitialDocument:
            decisionHandler(.allow)
        case .routeToCanonical(let destinationURL):
            host?.dismissReader()
            navigate(destinationURL)
            decisionHandler(.cancel)
        case .cancel:
            decisionHandler(.cancel)
        }
    }
}
