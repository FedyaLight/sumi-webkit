import Foundation
import Navigation
import SumiDomain
import WebKit

/// Attaches `Sec-GPC: 1` to outgoing main-frame navigation requests, mirroring
/// the DOM signal from `SumiGPCUserScript` so servers that only look at the
/// request header (rather than executing JS) still see Global Privacy Control.
///
/// WebKit's public API has no way to mutate an in-flight `WKNavigationAction`'s
/// request, so this follows the same approach DuckDuckGo's browsers use: cancel
/// the navigation and reissue it via `webView.load(_:)` with the header added.
/// `SumiGPCRequestFactory` guarantees this only fires once per request (it
/// returns `nil` once the header is already present), so the reissued load is
/// let through as `.next` on its second pass through the responder chain.
@MainActor
final class SumiGPCNavigationResponder: SumiNavigationActionTargetContextResponding {
    private weak var tab: Tab?
    private let requestFactory: SumiGPCRequestFactory
    private let isGPCEnabledProvider: () -> Bool

    init(
        tab: Tab,
        requestFactory: SumiGPCRequestFactory = SumiGPCRequestFactory(),
        isGPCEnabledProvider: (() -> Bool)? = nil
    ) {
        self.tab = tab
        self.requestFactory = requestFactory
        self.isGPCEnabledProvider = isGPCEnabledProvider ?? { [weak tab] in
            tab?.sumiSettings?.isGPCEnabled ?? true
        }
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        targetWebView: WKWebView?,
        context: SumiNavigationActionContext,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard navigationAction.isForMainFrame,
              let targetWebView,
              let rewrittenRequest = requestFactory.requestAddingGPCHeaderIfNeeded(
                  to: navigationAction.request,
                  isGPCEnabled: isGPCEnabledProvider()
        )
        else { return .next }

        guard let originalNavigationID = context.navigationID,
              let originalNavigationLifetime = context.navigationLifetime,
              let tab,
              let navigator = targetWebView.navigator(),
              let targetURL = rewrittenRequest.url else {
            return .cancel
        }
        let originalRole = tab.beginMainFrameLifecycle(
            from: targetWebView,
            navigationID: originalNavigationID,
            navigationLifetime: originalNavigationLifetime,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: navigationAction.isUserInitiated,
            continuationKind: nil
        )
        guard originalRole.isParticipant,
              let replacementNavigation = targetWebView.load(rewrittenRequest) else {
            return .cancel
        }
        let expectedNavigation = navigator.expect(replacementNavigation)
        let replacementRole = tab.beginMainFrameLifecycle(
            from: targetWebView,
            navigationID: expectedNavigation.stableIdentifier,
            navigationLifetime: expectedNavigation.identityLifetime,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .requestRewrite
        )
        precondition(
            replacementRole.isParticipant,
            "GPC request rewrite lost its exact navigation transaction"
        )
        return .cancel
    }
}
