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

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        for navigation: Navigation?
    ) async -> AuthChallengeDisposition? {
        guard let responder = target as? any SumiNavigationAuthChallengeResponding else { return .next }
        let decision = await responder.didReceive(
            authenticationChallenge,
            context: navigation.map(SumiNavigationContext.init)
        )
        return decision?.navigationAuthChallengeDisposition
    }

    func willStart(_ navigation: Navigation) {
        guard let responder = target as? any SumiNavigationStartResponding else { return }
        responder.navigationWillStart(SumiNavigationContext(navigation))
    }

    func didStart(_ navigation: Navigation) {
        guard let responder = target as? any SumiNavigationStartResponding else { return }
        responder.navigationDidStart(SumiNavigationContext(navigation))
    }

    func didCommit(_ navigation: Navigation) {
        guard let responder = target as? any SumiNavigationCommitResponding else { return }
        responder.navigationDidCommit(SumiNavigationContext(navigation))
    }

    func navigationDidFinish(_ navigation: Navigation) {
        guard let responder = target as? any SumiNavigationCompletionResponding else { return }
        responder.navigationDidFinish(SumiNavigationContext(navigation))
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard let responder = target as? any SumiNavigationCompletionResponding else { return }
        responder.navigationDidFail(error, context: SumiNavigationContext(navigation))
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        guard let responder = target as? any SumiSameDocumentNavigationResponding else { return }
        responder.navigationDidSameDocumentNavigation(
            type: navigationType.sumiSameDocumentNavigationType,
            context: SumiNavigationContext(navigation)
        )
    }

    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        guard let responder = target as? any SumiNavigationDownloadResponding else { return }
        responder.navigationAction(SumiNavigationAction(navigationAction), didBecome: SumiWebKitNavigationDownload(download))
    }

    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        guard let responder = target as? any SumiNavigationDownloadResponding else { return }
        responder.navigationResponse(
            SumiNavigationResponse(navigationResponse),
            didBecome: SumiWebKitNavigationDownload(download, response: navigationResponse.response)
        )
    }

    private func webView(for navigationAction: NavigationAction) -> WKWebView? {
        navigationAction.targetFrame?.webView ?? navigationAction.sourceFrame.webView
    }
}

private extension SumiNavigationContext {
    @MainActor
    init(_ navigation: Navigation) {
        let action = SumiNavigationAction(navigation.navigationAction)
        self.init(
            action: action,
            url: navigation.request.url,
            isCurrent: navigation.isCurrent,
            isMainFrame: navigation.navigationAction.isForMainFrame,
            webView: navigation.navigationAction.targetFrame?.webView ?? navigation.navigationAction.sourceFrame.webView
        )
    }
}

private final class SumiWebKitNavigationDownload: SumiNavigationDownload {
    private let download: WebKitDownload
    let response: URLResponse?

    init(_ download: WebKitDownload, response: URLResponse? = nil) {
        self.download = download
        self.response = response
    }

    var webKitDownload: WKDownload? {
        download as? WKDownload
    }

    var originalRequest: URLRequest? {
        download.originalRequest
    }

    var originatingWebView: WKWebView? {
        download.originatingWebView
    }

    var targetWebView: WKWebView? {
        download.targetWebView
    }

    var delegate: WKDownloadDelegate? {
        get { download.delegate }
        set { download.delegate = newValue }
    }

    func cancel(_ completionHandler: ((Data?) -> Void)?) {
        download.cancel(completionHandler)
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
