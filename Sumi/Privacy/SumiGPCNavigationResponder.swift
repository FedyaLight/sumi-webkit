import Foundation
import Navigation
import OSLog
import SumiDomain
import WebKit

enum SumiGPCNavigationRewriteFailure: String, CaseIterable, Equatable, Error, Sendable {
    case missingOriginalNavigationIdentity
    case originalNavigationIdentityMismatch
    case unavailableTransactionRuntime
    case missingTargetURL
    case originalTransactionMismatch
    case replacementLoadRejected
    case replacementNavigationIdentityMismatch
    case replacementTransactionMismatch
}

enum SumiGPCNavigationRewriteResult: Equatable {
    case rewritten
    case failed(SumiGPCNavigationRewriteFailure)
}

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
    private static let log = Logger.sumi(category: "GlobalPrivacyControl")

    private weak var tab: Tab?
    private let requestFactory: SumiGPCRequestFactory
    private let isGPCEnabledProvider: () -> Bool
    private let recordDiagnostic: (SumiGPCNavigationRewriteFailure) -> Void

    init(
        tab: Tab,
        requestFactory: SumiGPCRequestFactory = SumiGPCRequestFactory(),
        isGPCEnabledProvider: (() -> Bool)? = nil,
        recordDiagnostic: ((SumiGPCNavigationRewriteFailure) -> Void)? = nil
    ) {
        self.tab = tab
        self.requestFactory = requestFactory
        self.isGPCEnabledProvider = isGPCEnabledProvider ?? { [weak tab] in
            tab?.sumiSettings?.isGPCEnabled ?? true
        }
        self.recordDiagnostic = recordDiagnostic ?? { failure in
            Self.log.error(
                "GPC request rewrite failed: \(failure.rawValue, privacy: .public)"
            )
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

        let result = rewrite(
            rewrittenRequest,
            for: navigationAction,
            targetWebView: targetWebView,
            context: context
        )
        switch result {
        case .rewritten:
            return .cancel
        case .failed(let failure):
            recordDiagnostic(failure)
            return .cancel
        }
    }

    private func rewrite(
        _ rewrittenRequest: URLRequest,
        for navigationAction: SumiNavigationAction,
        targetWebView: WKWebView,
        context: SumiNavigationActionContext
    ) -> SumiGPCNavigationRewriteResult {
        guard let originalNavigationID = context.navigationID,
              let originalNavigationLifetime = context.navigationLifetime else {
            return .failed(.missingOriginalNavigationIdentity)
        }
        guard ObjectIdentifier(originalNavigationLifetime) == originalNavigationID else {
            return .failed(.originalNavigationIdentityMismatch)
        }
        guard let tab,
              targetWebView.navigationDelegate is DistributedNavigationDelegate,
              let navigator = targetWebView.navigator() else {
            return .failed(.unavailableTransactionRuntime)
        }
        guard let targetURL = rewrittenRequest.url else {
            return .failed(.missingTargetURL)
        }
        let originalRole = tab.beginMainFrameLifecycle(
            from: targetWebView,
            navigationID: originalNavigationID,
            navigationLifetime: originalNavigationLifetime,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: navigationAction.isUserInitiated,
            continuationKind: nil
        )
        guard originalRole.isParticipant else {
            return .failed(.originalTransactionMismatch)
        }
        guard let replacementNavigation = targetWebView.load(rewrittenRequest) else {
            return .failed(.replacementLoadRejected)
        }
        let expectedNavigation = navigator.expect(replacementNavigation)
        guard ObjectIdentifier(expectedNavigation.identityLifetime)
            == expectedNavigation.stableIdentifier else {
            stopRejectedRewrite(on: targetWebView)
            return .failed(.replacementNavigationIdentityMismatch)
        }
        let replacementRole = tab.beginMainFrameLifecycle(
            from: targetWebView,
            navigationID: expectedNavigation.stableIdentifier,
            navigationLifetime: expectedNavigation.identityLifetime,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .requestRewrite
        )
        guard replacementRole.isParticipant else {
            stopRejectedRewrite(on: targetWebView)
            return .failed(.replacementTransactionMismatch)
        }
        return .rewritten
    }

    private func stopRejectedRewrite(on webView: WKWebView) {
        // WebKit has no public per-WKNavigation cancellation API. Stop the
        // load immediately so a request outside the exact transaction cannot
        // proceed with stale GPC rewrite state.
        webView.stopLoading()
    }
}
