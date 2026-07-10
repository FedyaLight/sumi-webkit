import SumiWebRuntime
import WebKit

/// Owns exact-WebView crash repair requirements. Navigation authority decides
/// replica-versus-global scope; this planner only guards the physical recovery
/// marker against ObjectIdentifier reuse (ABA).
@MainActor
final class TabWebContentRecoveryPlanner {
    private typealias WeakWebViewReference = WebViewIdentityWitness

    private var requirementsByWebViewID: [
        ObjectIdentifier: WeakWebViewReference
    ] = [:]

    /// Returns false when the exact WebView already has an outstanding marker.
    func markRequired(on webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        if requirementsByWebViewID[webViewID]?.matches(webView) == true {
            return false
        }
        requirementsByWebViewID[webViewID] = WeakWebViewReference(webView)
        return true
    }

    func requiresRecovery(on webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let requirement = requirementsByWebViewID[webViewID] else {
            return false
        }
        guard requirement.matches(webView) else {
            requirementsByWebViewID.removeValue(forKey: webViewID)
            return false
        }
        return true
    }

    func finish(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard requirementsByWebViewID[webViewID]?.matches(webView) == true else {
            return
        }
        requirementsByWebViewID.removeValue(forKey: webViewID)
    }

    func remove(_ webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard requirementsByWebViewID[webViewID]?.matches(webView) == true else {
            return
        }
        requirementsByWebViewID.removeValue(forKey: webViewID)
    }
}
