import AppKit
import WebKit

enum SumiReaderRemoteResourcePolicy: Equatable {
    /// The source document has no active WebKit rule-list attachment. Reader
    /// may use the source profile's exact data store for remote article media.
    case sourceProfileWithoutRuleLists
    /// WebKit does not expose the rule lists attached to an existing content
    /// controller. Reader therefore denies remote subresources instead of
    /// silently loading them without the source document's protection.
    case denyRemoteResources

    var allowsRemoteResources: Bool {
        self == .sourceProfileWithoutRuleLists
    }
}

/// The exact committed document underneath one Reader presentation. It binds
/// every Reader command to the physical canonical WebView and the lease that
/// was current when the article was extracted.
@MainActor
struct SumiReaderSourceDocument {
    typealias CurrentLease = @MainActor () -> TabMainFrameDocumentLease?
    typealias RouteWebLink = @MainActor (
        _ url: URL,
        _ behavior: SumiLinkOpenBehavior
    ) -> Bool
    typealias RouteExternalLink = @MainActor (
        _ navigationAction: SumiNavigationAction
    ) async -> Void
    typealias IsGlanceTrigger = @MainActor (
        _ modifierFlags: NSEvent.ModifierFlags
    ) -> Bool
    typealias RouteGlance = @MainActor (
        _ url: URL,
        _ originRectInWindow: CGRect?
    ) -> Bool

    let webView: WKWebView
    let lease: TabMainFrameDocumentLease
    let sourceURL: URL
    let remoteResourcePolicy: SumiReaderRemoteResourcePolicy

    private let currentLease: CurrentLease
    private let routeWebLinkAction: RouteWebLink
    private let routeExternalLinkAction: RouteExternalLink
    private let isGlanceTriggerAction: IsGlanceTrigger
    private let routeGlanceAction: RouteGlance

    init(
        webView: WKWebView,
        lease: TabMainFrameDocumentLease,
        sourceURL: URL,
        remoteResourcePolicy: SumiReaderRemoteResourcePolicy,
        currentLease: @escaping CurrentLease,
        routeWebLink: @escaping RouteWebLink,
        routeExternalLink: @escaping RouteExternalLink,
        isGlanceTrigger: @escaping IsGlanceTrigger = { _ in false },
        routeGlance: @escaping RouteGlance = { _, _ in false }
    ) {
        self.webView = webView
        self.lease = lease
        self.sourceURL = sourceURL
        self.remoteResourcePolicy = remoteResourcePolicy
        self.currentLease = currentLease
        self.routeWebLinkAction = routeWebLink
        self.routeExternalLinkAction = routeExternalLink
        self.isGlanceTriggerAction = isGlanceTrigger
        self.routeGlanceAction = routeGlance
    }

    var isCurrent: Bool {
        ObjectIdentifier(webView) == lease.webViewID
            && currentLease() == lease
    }

    @discardableResult
    func routeWebLink(
        _ url: URL,
        behavior: SumiLinkOpenBehavior
    ) -> Bool {
        guard isCurrent else { return false }
        return routeWebLinkAction(url, behavior)
    }

    func routeExternalLink(_ navigationAction: SumiNavigationAction) async {
        guard isCurrent else { return }
        await routeExternalLinkAction(navigationAction)
    }

    func isGlanceTrigger(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        isCurrent && isGlanceTriggerAction(modifierFlags)
    }

    @discardableResult
    func routeGlance(
        _ url: URL,
        originRectInWindow: CGRect?
    ) -> Bool {
        guard isCurrent else { return false }
        return routeGlanceAction(url, originRectInWindow)
    }
}

struct SumiReaderNavigationPolicy {
    enum Decision: Equatable {
        case allowInitialDocument
        case allowReaderFragment
        case routeGlance(URL, fallback: SumiLinkOpenBehavior)
        case routeWebLink(URL, SumiLinkOpenBehavior)
        case routeExternalLink(URL)
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
        isTargetingNewWindow: Bool,
        destinationURL: URL?,
        sourceURL: URL,
        buttonIsMiddle: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        isGlanceRequested: Bool = false,
        shouldDownload: Bool = false
    ) -> Decision {
        if navigationType == .linkActivated {
            guard phase == .presented,
                  let destinationURL,
                  let scheme = destinationURL.scheme?.lowercased()
            else {
                return .cancel
            }

            if Self.isLocalFragmentNavigation(
                destinationURL,
                sourceURL: sourceURL
            ), isTargetingNewWindow == false, isMainFrame == true {
                return .allowReaderFragment
            }

            if scheme == "http" || scheme == "https" {
                // Reader has no download delegate/runtime of its own. Never
                // degrade a request-preserving download into URL-only routing.
                guard shouldDownload == false else { return .cancel }
                let behavior = SumiLinkOpenBehavior(
                    buttonIsMiddle: buttonIsMiddle,
                    modifierFlags: modifierFlags,
                    switchToNewTabWhenOpenedPreference: false,
                    canOpenLinkInCurrentTab: isTargetingNewWindow == false,
                    shouldSelectNewTab: isTargetingNewWindow
                )
                if isGlanceRequested,
                   destinationURL.sumiIsGlancePreviewableLink {
                    return .routeGlance(
                        destinationURL,
                        fallback: behavior
                    )
                }
                if behavior == .currentTab {
                    phase = .terminated
                }
                return .routeWebLink(destinationURL, behavior)
            }

            if (scheme == "mailto" || scheme == "tel"),
               SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(
                   destinationURL
               ) {
                return .routeExternalLink(destinationURL)
            }
            return .cancel
        }

        // A URL-only browser command cannot preserve form method/body. Reader
        // stays fail-closed until request-preserving canonical navigation exists.
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

    private static func isLocalFragmentNavigation(
        _ destinationURL: URL,
        sourceURL: URL
    ) -> Bool {
        guard destinationURL.fragment?.isEmpty == false else { return false }
        var destination = URLComponents(
            url: destinationURL,
            resolvingAgainstBaseURL: false
        )
        var source = URLComponents(
            url: sourceURL,
            resolvingAgainstBaseURL: false
        )
        destination?.fragment = nil
        source?.fragment = nil
        return destination?.url == source?.url
    }
}

/// View-local Reader representation. It never becomes a Tab navigation
/// participant: the canonical WebView, history, permission identity and
/// cross-window authority stay untouched underneath this ephemeral surface.
@MainActor
final class ReaderPresentationSession: NSObject, WKNavigationDelegate {
    let sourceDocument: SumiReaderSourceDocument
    let webView: FocusableWKWebView

    var sourceDocumentLease: TabMainFrameDocumentLease {
        sourceDocument.lease
    }

    private let linkInteractionScript: SumiLinkInteractionUserScript
    private weak var host: SumiWebViewContainerView?
    private var navigationPolicy = SumiReaderNavigationPolicy()
    private var isInvalidated = false

    init?(sourceDocument: SumiReaderSourceDocument) {
        guard sourceDocument.isCurrent,
              let configuration = Self.readerConfiguration(
                  from: sourceDocument.webView
              ) else {
            return nil
        }
        self.sourceDocument = sourceDocument

        let linkInteractionScript = SumiLinkInteractionUserScript(contextID: UUID())
        self.linkInteractionScript = linkInteractionScript
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let contentWorld = linkInteractionScript.getContentWorld()
        for messageName in linkInteractionScript.messageNames {
            userContentController.add(
                linkInteractionScript,
                contentWorld: contentWorld,
                name: messageName
            )
        }
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: linkInteractionScript)
        )
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
        webView.loadHTMLString(html, baseURL: sourceDocument.sourceURL)
    }

    /// Reader owns a dedicated content controller containing only the minimal
    /// link-interaction transport. Detaching its native handlers immediately
    /// severs publication; the controller and its one immutable user script
    /// then die with this non-reusable Reader WebView.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        let userContentController = webView.configuration.userContentController
        let contentWorld = linkInteractionScript.getContentWorld()
        for messageName in linkInteractionScript.messageNames {
            userContentController.removeScriptMessageHandler(
                forName: messageName,
                contentWorld: contentWorld
            )
        }
        webView.resetPageInteractionState()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard sourceDocument.isCurrent else {
            dismissStalePresentation()
            decisionHandler(.cancel)
            return
        }

        let modifierFlags: NSEvent.ModifierFlags
        let buttonIsMiddle: Bool
        if let readerWebView = webView as? FocusableWKWebView {
            modifierFlags = readerWebView.gestures.resolvedModifierFlags(
                actionFlags: navigationAction.modifierFlags
            )
            buttonIsMiddle = navigationAction.buttonNumber == 2
                || readerWebView.gestures.hasRecentAuxiliaryMouseDown
        } else {
            modifierFlags = navigationAction.modifierFlags
            buttonIsMiddle = false
        }
        let adaptedAction = SumiNavigationAction(
            webKitNavigationAction: navigationAction
        )
        let isGlanceRequested = sourceDocument.isGlanceTrigger(modifierFlags)

        switch navigationPolicy.decide(
            navigationType: navigationAction.navigationType,
            isMainFrame: navigationAction.targetFrame?.isMainFrame,
            isTargetingNewWindow: navigationAction.targetFrame == nil,
            destinationURL: navigationAction.request.url,
            sourceURL: sourceDocument.sourceURL,
            buttonIsMiddle: buttonIsMiddle,
            modifierFlags: modifierFlags,
            isGlanceRequested: isGlanceRequested,
            shouldDownload: adaptedAction.shouldDownload
        ) {
        case .allowInitialDocument, .allowReaderFragment:
            decisionHandler(.allow)
        case .routeGlance(let destinationURL, let fallback):
            let readerWebView = webView as? FocusableWKWebView
            let didPresent = sourceDocument.routeGlance(
                destinationURL,
                originRectInWindow: readerWebView?.gestures
                    .recentGlanceOriginRect(maxAge: 2)
            )
            if didPresent {
                readerWebView?.consumeGestureForBrowserCommand()
            } else {
                if fallback == .currentTab {
                    host?.dismissReader()
                }
                _ = sourceDocument.routeWebLink(
                    destinationURL,
                    behavior: fallback
                )
            }
            decisionHandler(.cancel)
        case .routeWebLink(let destinationURL, let behavior):
            if behavior == .currentTab {
                host?.dismissReader()
            }
            let didRoute = sourceDocument.routeWebLink(
                destinationURL,
                behavior: behavior
            )
            if didRoute == false, sourceDocument.isCurrent == false {
                dismissStalePresentation()
            }
            decisionHandler(.cancel)
        case .routeExternalLink:
            decisionHandler(.cancel)
            Task { @MainActor [weak self] in
                guard let self else { return }
                await sourceDocument.routeExternalLink(adaptedAction)
                if sourceDocument.isCurrent == false {
                    dismissStalePresentation()
                }
            }
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    private func dismissStalePresentation() {
        guard let host, host.hasReaderPresentation(
            matching: sourceDocumentLease
        ) else { return }
        host.dismissReader()
    }

    private static func readerConfiguration(
        from sourceWebView: WKWebView
    ) -> WKWebViewConfiguration? {
        guard let configuration = sourceWebView.configuration.copy()
            as? WKWebViewConfiguration else {
            return nil
        }
        // `copy()` preserves the exact process/data-store/media configuration.
        // The content controller is replaced in init so normal-tab scripts and
        // their Tab authority can never execute inside Reader.
        configuration.websiteDataStore = sourceWebView.configuration.websiteDataStore
        configuration.webExtensionController = nil
        configuration.sumiIsNormalTabWebViewConfiguration = false
        return configuration
    }
}
