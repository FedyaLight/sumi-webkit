import WebKit

/// Mutation authority held only by the runtime transaction and the WebKit
/// lifecycle responder that validates callback ownership.
@MainActor
protocol TabWebContentRecoveryAdmission: AnyObject {
    func beginRecovery(on webView: WKWebView) -> TabWebContentProcessRecoveryPlan
}

/// Read-only marker visibility used by routing and registration services.
@MainActor
protocol TabWebContentRecoveryMarkerQuery: AnyObject {
    func isRecoveryRequired(on webView: WKWebView) -> Bool
}
