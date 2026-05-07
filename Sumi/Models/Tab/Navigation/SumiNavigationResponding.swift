import WebKit

enum SumiWebsiteAutoplayPolicy: UInt, Equatable {
    case `default`
    case allow
    case allowWithoutSound
    case deny
}

struct SumiNavigationPreferences: Equatable {
    var userAgent: String?
    var contentMode: WKWebpagePreferences.ContentMode
    var javaScriptEnabled: Bool
    var autoplayPolicy: SumiWebsiteAutoplayPolicy?
    var mustApplyAutoplayPolicy: Bool
}

@MainActor
protocol SumiNavigationActionResponding: AnyObject {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy?
}

@MainActor
protocol SumiNavigationActionWebViewResponding: SumiNavigationActionResponding {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView: WKWebView?,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy?
}

extension SumiNavigationActionWebViewResponding {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        await decidePolicy(for: navigationAction, webView: nil, preferences: &preferences)
    }
}

@MainActor
protocol SumiNavigationResponseResponding: AnyObject {
    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy?
}

@MainActor
protocol SumiNavigationCompletionResponding: AnyObject {
    func navigationDidFinish()
    func navigationDidFail()
}

@MainActor
protocol SumiNavigationStartResponding: AnyObject {
    func navigationDidStart()
}

@MainActor
protocol SumiNavigationAuthChallengeResponding: AnyObject {
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition?
}

@MainActor
protocol SumiSameDocumentNavigationResponding: AnyObject {
    func navigationDidSameDocumentNavigation(type: SumiSameDocumentNavigationType)
}

@MainActor
protocol SumiNavigationDownloadResponding: AnyObject {
    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload)
    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload)
}

protocol SumiNavigationDownload: AnyObject {
    var webKitDownload: WKDownload? { get }
    var response: URLResponse? { get }
    var originalRequest: URLRequest? { get }
    var originatingWebView: WKWebView? { get }
    var targetWebView: WKWebView? { get }
    var delegate: WKDownloadDelegate? { get set }
    func cancel(_ completionHandler: ((Data?) -> Void)?)
}
