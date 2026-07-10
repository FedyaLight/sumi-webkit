import Foundation
import SumiDomain
import WebKit

struct SumiNavigationContext {
    let navigationID: ObjectIdentifier
    let navigationLifetime: AnyObject
    let action: SumiNavigationAction?
    let url: URL?
    let isCurrent: Bool?
    let isCommitted: Bool?
    let isMainFrame: Bool?
    let webView: WKWebView?

    init(
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        action: SumiNavigationAction?,
        url: URL?,
        isCurrent: Bool?,
        isCommitted: Bool? = nil,
        isMainFrame: Bool?,
        webView: WKWebView?
    ) {
        self.navigationID = navigationID
        self.navigationLifetime = navigationLifetime
        self.action = action
        self.url = url
        self.isCurrent = isCurrent
        self.isCommitted = isCommitted
        self.isMainFrame = isMainFrame
        self.webView = webView
    }
}

enum SumiMainFrameNavigationTerminationReason: Equatable {
    case actionCancelled
    case actionBecameDownload
    case responseBecameDownload
}

struct SumiMainFrameNavigationTermination {
    let navigationID: ObjectIdentifier
    let navigationLifetime: AnyObject
    let webView: WKWebView
    let reason: SumiMainFrameNavigationTerminationReason
}

struct SumiNavigationActionContext {
    let navigationID: ObjectIdentifier?
    let navigationLifetime: AnyObject?

    init(
        navigationID: ObjectIdentifier?,
        navigationLifetime: AnyObject? = nil
    ) {
        self.navigationID = navigationID
        self.navigationLifetime = navigationLifetime
    }
}

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

@MainActor
protocol SumiNavigationActionContextResponding: SumiNavigationActionWebViewResponding {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView: WKWebView?,
        context: SumiNavigationActionContext,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy?
}

extension SumiNavigationActionContextResponding {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        webView: WKWebView?,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        await decidePolicy(
            for: navigationAction,
            webView: webView,
            context: SumiNavigationActionContext(navigationID: nil),
            preferences: &preferences
        )
    }
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
protocol SumiNavigationResponseContextResponding: SumiNavigationResponseResponding {
    func decidePolicy(
        for navigationResponse: SumiNavigationResponse,
        context: SumiNavigationContext?
    ) async -> SumiNavigationResponsePolicy?
}

extension SumiNavigationResponseContextResponding {
    func decidePolicy(
        for navigationResponse: SumiNavigationResponse
    ) async -> SumiNavigationResponsePolicy? {
        await decidePolicy(for: navigationResponse, context: nil)
    }
}

@MainActor
protocol SumiNavigationCompletionResponding: AnyObject {
    func navigationDidFinish()
    func navigationDidFinish(_ context: SumiNavigationContext?)
    func navigationDidFail()
    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?)
}

@MainActor
protocol SumiNavigationTerminalResponding: AnyObject {
    func mainFrameNavigationDidTerminate(
        _ termination: SumiMainFrameNavigationTermination
    )
    func webContentProcessDidTerminate(on webView: WKWebView)
}

extension SumiNavigationCompletionResponding {
    func navigationDidFinish() {}

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        navigationDidFinish()
    }

    func navigationDidFail() {}

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        navigationDidFail()
    }
}

@MainActor
protocol SumiNavigationStartResponding: AnyObject {
    func navigationWillStart(_ context: SumiNavigationContext)
    func navigationDidStart()
    func navigationDidStart(_ context: SumiNavigationContext)
}

extension SumiNavigationStartResponding {
    func navigationWillStart(_ context: SumiNavigationContext) {}

    func navigationDidStart() {}

    func navigationDidStart(_ context: SumiNavigationContext) {
        navigationDidStart()
    }
}

@MainActor
protocol SumiNavigationCommitResponding: AnyObject {
    func navigationDidCommit(_ context: SumiNavigationContext)
}

@MainActor
protocol SumiNavigationAuthChallengeResponding: AnyObject {
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition?
    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition?
}

extension SumiNavigationAuthChallengeResponding {
    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge)
    }
}

@MainActor
protocol SumiSameDocumentNavigationResponding: AnyObject {
    func navigationDidSameDocumentNavigation(type: SumiSameDocumentNavigationType)
    func navigationDidSameDocumentNavigation(
        type: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    )
}

extension SumiSameDocumentNavigationResponding {
    func navigationDidSameDocumentNavigation(type: SumiSameDocumentNavigationType) {}

    func navigationDidSameDocumentNavigation(
        type: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        navigationDidSameDocumentNavigation(type: type)
    }
}

@MainActor
protocol SumiNavigationDownloadResponding: AnyObject {
    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload)
    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload)
}

@MainActor
protocol SumiNavigationDownload: AnyObject {
    var webKitDownload: WKDownload? { get }
    var response: URLResponse? { get }
    var originalRequest: URLRequest? { get }
    var originatingWebView: WKWebView? { get }
    var targetWebView: WKWebView? { get }
    var delegate: WKDownloadDelegate? { get set }
    func cancel(_ completionHandler: (@MainActor @Sendable (Data?) -> Void)?)
}
