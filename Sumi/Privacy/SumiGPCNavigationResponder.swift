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

/// Enables WebKit's native GPC navigation preference when the runtime exposes
/// it. On older WebKit versions, attaches `Sec-GPC: 1` to outgoing main-frame
/// navigation requests, mirroring the DOM signal from `SumiGPCUserScript`.
///
/// The compatibility path cannot mutate an in-flight `WKNavigationAction`, so
/// it cancels and reissues eligible requests via `webView.load(_:)`.
/// `SumiGPCRequestFactory` keeps that rewrite idempotent.
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
            tab?.sumiSettings?.isGPCEnabled ?? false
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
        guard navigationAction.isForMainFrame else { return .next }

        let isGPCEnabled = isGPCEnabledProvider()
        if preferences.globalPrivacyControlEnabled != nil {
            preferences.globalPrivacyControlEnabled = isGPCEnabled
            return .next
        }

        guard let targetWebView,
              let rewrittenRequest = requestFactory.requestAddingGPCHeaderIfNeeded(
                  to: navigationAction.request,
                  isGPCEnabled: isGPCEnabled
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
