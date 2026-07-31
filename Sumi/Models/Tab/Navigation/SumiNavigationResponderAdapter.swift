import Navigation
import WebKit
import SumiDomain

@MainActor
final class SumiNavigationResponderAdapter: NavigationResponder {
    private weak var target: AnyObject?
    private weak var installedWebView: WKWebView?
    private var authenticationChallengeWaitCount = 0

    init(target: AnyObject) {
        self.target = target
    }

    func isAdapting<T: AnyObject>(_ _: T.Type) -> Bool {
        target is T
    }

    func bind(to webView: WKWebView) {
        installedWebView = webView
    }

    var shouldDisableLongDecisionMakingChecks: Bool {
        authenticationChallengeWaitCount > 0
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        guard let responder = target as? any SumiNavigationActionResponding else { return .next }
        var sumiPreferences = SumiNavigationPreferences(preferences)
        let sumiAction = SumiNavigationAction(navigationAction)
        let decision: SumiNavigationActionPolicy?
        if let responder = responder as? any SumiNavigationActionTargetContextResponding {
            decision = await responder.decidePolicy(
                for: sumiAction,
                targetWebView: targetWebView(for: navigationAction),
                context: SumiNavigationActionContext(
                    navigationID: navigationAction.mainFrameNavigation.map(
                        ObjectIdentifier.init
                    ),
                    navigationLifetime: navigationAction.mainFrameNavigation
                ),
                preferences: &sumiPreferences
            )
        } else if let responder = responder as? any SumiNavigationActionSourceAndTargetWebViewResponding {
            decision = await responder.decidePolicy(
                for: sumiAction,
                sourceWebView: sourceWebView(for: navigationAction),
                targetWebView: targetWebView(for: navigationAction),
                preferences: &sumiPreferences
            )
        } else if let responder = responder as? any SumiNavigationActionSourceWebViewResponding {
            decision = await responder.decidePolicy(
                for: sumiAction,
                sourceWebView: sourceWebView(for: navigationAction),
                preferences: &sumiPreferences
            )
        } else if let responder = responder as? any SumiNavigationActionTargetWebViewResponding {
            decision = await responder.decidePolicy(
                for: sumiAction,
                targetWebView: targetWebView(for: navigationAction),
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
        let response = SumiNavigationResponse(navigationResponse)
        let decision: SumiNavigationResponsePolicy?
        if let contextualResponder = responder as? any SumiNavigationResponseContextResponding {
            decision = await contextualResponder.decidePolicy(
                for: response,
                context: navigationResponse.mainFrameNavigation.map(
                    SumiNavigationContext.init
                )
            )
        } else {
            decision = await responder.decidePolicy(for: response)
        }
        return decision?.navigationResponsePolicy
    }

    func didCancelNavigationAction(
        _ navigationAction: NavigationAction,
        withRedirectNavigations expectedNavigations: [ExpectedNavigation]?
    ) {
        guard navigationAction.isForMainFrame,
              let webView = navigationWebView(for: navigationAction),
              let responder = target as? any SumiNavigationTerminalResponding else {
            return
        }
        var navigationLifetimes: [ObjectIdentifier: AnyObject] = [:]
        if let navigation = navigationAction.mainFrameNavigation {
            navigationLifetimes[ObjectIdentifier(navigation)] = navigation
        }
        for expectedNavigation in expectedNavigations ?? [] {
            navigationLifetimes[expectedNavigation.stableIdentifier]
                = expectedNavigation.identityLifetime
        }
        for (navigationID, navigationLifetime) in navigationLifetimes {
            responder.mainFrameNavigationDidTerminate(
                SumiMainFrameNavigationTermination(
                    navigationID: navigationID,
                    navigationLifetime: navigationLifetime,
                    webView: webView,
                    reason: .actionCancelled
                )
            )
        }
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        for navigation: Navigation?
    ) async -> AuthChallengeDisposition? {
        guard let responder = target as? any SumiNavigationAuthChallengeResponding else { return .next }
        authenticationChallengeWaitCount += 1
        defer { authenticationChallengeWaitCount -= 1 }
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

    func navigationAction(
        _ navigationAction: NavigationAction,
        willBecomeDownloadIn webView: WKWebView
    ) {
        notifyDownloadTermination(
            navigation: navigationAction.mainFrameNavigation,
            webView: webView,
            isMainFrame: navigationAction.isForMainFrame,
            reason: .actionBecameDownload
        )
    }

    func navigationResponse(
        _ navigationResponse: NavigationResponse,
        willBecomeDownloadIn webView: WKWebView
    ) {
        notifyDownloadTermination(
            navigation: navigationResponse.mainFrameNavigation,
            webView: webView,
            isMainFrame: navigationResponse.isForMainFrame,
            reason: .responseBecameDownload
        )
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

    func webContentProcessDidTerminate(with _: WKProcessTerminationReason?) {
        guard let webView = installedWebView,
              let responder = target as? any SumiNavigationTerminalResponding else {
            return
        }
        responder.webContentProcessDidTerminate(on: webView)
    }

    private func sourceWebView(for navigationAction: NavigationAction) -> WKWebView? {
        navigationAction.sourceFrame.webView
    }

    private func targetWebView(for navigationAction: NavigationAction) -> WKWebView? {
        navigationAction.targetFrame?.webView
    }

    private func navigationWebView(for navigationAction: NavigationAction) -> WKWebView? {
        targetWebView(for: navigationAction) ?? sourceWebView(for: navigationAction)
    }

    private func notifyDownloadTermination(
        navigation: Navigation?,
        webView: WKWebView,
        isMainFrame: Bool,
        reason: SumiMainFrameNavigationTerminationReason
    ) {
        guard isMainFrame,
              let navigation,
              let responder = target as? any SumiNavigationTerminalResponding else {
            return
        }
        responder.mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                webView: webView,
                reason: reason
            )
        )
    }
}

private extension SumiNavigationContext {
    @MainActor
    init(_ navigation: Navigation) {
        let action = SumiNavigationAction(navigation.navigationAction)
        self.init(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: action,
            url: navigation.request.url,
            isCurrent: navigation.isCurrent,
            isCommitted: navigation.isCommitted,
            isMainFrame: navigation.navigationAction.isForMainFrame,
            webView: navigation.navigationAction.targetFrame?.webView ?? navigation.navigationAction.sourceFrame.webView
        )
    }
}

@MainActor
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

    func cancel(_ completionHandler: (@MainActor @Sendable (Data?) -> Void)?) {
        download.cancel(completionHandler)
    }
}

private extension SumiNavigationPreferences {
    init(_ preferences: NavigationPreferences) {
        self.init(
            userAgent: preferences.userAgent,
            contentMode: preferences.contentMode,
            javaScriptEnabled: preferences.javaScriptEnabled,
            globalPrivacyControlEnabled: preferences.globalPrivacyControlEnabled,
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
        globalPrivacyControlEnabled = preferences.globalPrivacyControlEnabled
        autoplayPolicy = preferences.autoplayPolicy.flatMap { _WKWebsiteAutoplayPolicy(rawValue: $0.rawValue) }
        mustApplyAutoplayPolicy = preferences.mustApplyAutoplayPolicy
    }
}
