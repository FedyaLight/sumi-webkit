import SumiWebRuntime
import WebKit

/// Stores exact-WebView crash-repair markers. Scope and authority settlement
/// stay in `TabMainFrameRuntimeTransaction`; this ledger only protects marker
/// identity against `ObjectIdentifier` reuse.
@MainActor
final class TabWebContentRecoveryMarkerLedger {
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

    func isRecoveryRequired(on webView: WKWebView) -> Bool {
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

    func clear(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard requirementsByWebViewID[webViewID]?.matches(webView) == true else {
            return
        }
        requirementsByWebViewID.removeValue(forKey: webViewID)
    }
}
