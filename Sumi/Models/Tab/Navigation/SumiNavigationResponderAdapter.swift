import Navigation
import WebKit

@MainActor
final class SumiNavigationResponderAdapter: NavigationResponder {
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        guard let responder = target as? any SumiNavigationActionResponding else { return .next }
        var sumiPreferences = SumiNavigationPreferences(preferences)
        let sumiAction = SumiNavigationAction(navigationAction)
        let decision: SumiNavigationActionPolicy?
        if let responder = responder as? any SumiNavigationActionWebViewResponding {
            decision = await responder.decidePolicy(
                for: sumiAction,
                webView: webView(for: navigationAction),
                preferences: &sumiPreferences
            )
        } else {
            decision = await responder.decidePolicy(
                for: sumiAction,
                preferences: &sumiPreferences
            )
        }
        preferences.apply(sumiPreferences)
        return decision?.navigationActionPolicy
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        guard let responder = target as? any SumiNavigationResponseResponding else { return .next }
        let decision = await responder.decidePolicy(for: SumiNavigationResponse(navigationResponse))
        return decision?.navigationResponsePolicy
    }

    func navigationDidFinish(_: Navigation) {
        guard let responder = target as? any SumiNavigationCompletionResponding else { return }
        responder.navigationDidFinish()
    }

    func navigation(_: Navigation, didFailWith error: WKError) {
        guard let responder = target as? any SumiNavigationCompletionResponding else { return }
        responder.navigationDidFail()
    }

    private func webView(for navigationAction: NavigationAction) -> WKWebView? {
        navigationAction.targetFrame?.webView ?? navigationAction.sourceFrame.webView
    }
}

private extension SumiNavigationPreferences {
    init(_ preferences: NavigationPreferences) {
        self.init(
            userAgent: preferences.userAgent,
            contentMode: preferences.contentMode,
            javaScriptEnabled: preferences.javaScriptEnabled,
            autoplayPolicy: preferences.autoplayPolicy.flatMap { SumiWebsiteAutoplayPolicy(rawValue: $0.rawValue) },
            mustApplyAutoplayPolicy: preferences.mustApplyAutoplayPolicy
        )
    }
}

private extension NavigationPreferences {
    mutating func apply(_ preferences: SumiNavigationPreferences) {
        userAgent = preferences.userAgent
        contentMode = preferences.contentMode
        javaScriptEnabled = preferences.javaScriptEnabled
        autoplayPolicy = preferences.autoplayPolicy.flatMap { _WKWebsiteAutoplayPolicy(rawValue: $0.rawValue) }
        mustApplyAutoplayPolicy = preferences.mustApplyAutoplayPolicy
    }
}
