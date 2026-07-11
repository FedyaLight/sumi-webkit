import SumiWebRuntime
import WebKit

/// Exact configuration-policy admission for one Tab/WebView-session identity.
///
/// Provisioning may only prepare receipts against this session's current
/// generation. Placement code may then preflight before canonical mutation and
/// settle the same receipts after placement without reaching back through a
/// weak Tab closure.
@MainActor
final class TabConfigurationPolicyTransaction {
    private let policyLedger: TabConfigurationPolicyLedger
    let webViewSession: WebViewSessionHandle

    init(
        policyLedger: TabConfigurationPolicyLedger,
        webViewSession: WebViewSessionHandle
    ) {
        self.policyLedger = policyLedger
        self.webViewSession = webViewSession
    }

    func prepare(
        _ state: TabConfigurationPolicyState
    ) -> PreparedConfigurationPolicyChange {
        policyLedger.prepare(
            state,
            expectedSessionGeneration: webViewSession.generation
        )
    }

    func preparedChangeSet(
        for webViews: [WKWebView]
    ) -> PreparedConfigurationPolicyChangeSet? {
        PreparedConfigurationPolicyChangeSet(
            webViews: webViews,
            policyLedger: policyLedger
        )
    }

    func cancel(_ webViews: [WKWebView]) {
        for webView in webViews {
            guard let receipt = webView
                .sumiPreparedConfigurationPolicyChange,
                  receipt.belongs(to: policyLedger) else {
                continue
            }
            receipt.cancel()
            if webView.sumiPreparedConfigurationPolicyChange === receipt {
                webView.sumiPreparedConfigurationPolicyChange = nil
            }
        }
    }
}
