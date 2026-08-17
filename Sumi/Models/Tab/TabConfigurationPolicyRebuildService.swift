import Foundation

@MainActor
struct TabConfigurationPolicyRebuildService {
    private let webViewReplacement = TabWebViewReplacementService()

    func rebuildContentBlockingIfNeeded(
        in tab: Tab,
        targetURL: URL?,
        reason: String,
        policies: TabReloadPolicies,
        safari: SafariContentBlockerReloadState,
        protection: ProtectionReloadState,
        autoplay: AutoplayReloadState
    ) -> TabWebViewReplacementOutcome {
        let existingWebView = tab.resolvedCurrentWebView()
        let requiresProtectionRebuild = protection
            .requiresNormalWebViewRebuild(
                for: targetURL,
                existingWebView: existingWebView,
                webViewConfigurationOverride:
                    tab.webViewConfigurationOverride,
                isPopupHost: tab.isPopupHost,
                policy: policies.protection
            )
        let requiresSafariRebuild = safari
            .requiresNormalWebViewRebuild(
                for: targetURL,
                existingWebView: existingWebView,
                webViewConfigurationOverride:
                    tab.webViewConfigurationOverride,
                isPopupHost: tab.isPopupHost,
                policy: policies.safariContentBlockers
            )
        guard requiresProtectionRebuild || requiresSafariRebuild,
              existingWebView != nil else {
            return .notNeeded
        }

        let outcome = webViewReplacement.replaceNormalWebView(
            in: tab,
            targetURL: targetURL ?? tab.url,
            reason: reason
        )
        guard outcome.didReplace else { return outcome }

        tab.publishNavigationStateChangeIfNeeded(
            safari.updateRequirement(
                currentURL: tab.url,
                existingWebView: tab.resolvedCurrentWebView(),
                policy: policies.safariContentBlockers
            )
        )
        tab.publishNavigationStateChangeIfNeeded(
            protection.updateRequirement(
                currentURL: tab.url,
                existingWebView: tab.resolvedCurrentWebView(),
                policy: policies.protection
            )
        )
        tab.publishNavigationStateChangeIfNeeded(
            autoplay.updateRequirement(
                currentURL: tab.url,
                existingWebView: tab.resolvedCurrentWebView(),
                profile: tab.resolveProfile(),
                policy: policies.autoplay
            )
        )
        return outcome
    }

    func rebuildAutoplayIfNeeded(
        in tab: Tab,
        targetURL: URL?,
        reason: String,
        policies: TabReloadPolicies,
        autoplay: AutoplayReloadState
    ) -> TabWebViewReplacementOutcome {
        guard autoplay.requiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: tab.resolvedCurrentWebView(),
            webViewConfigurationOverride: tab.webViewConfigurationOverride,
            isPopupHost: tab.isPopupHost,
            profile: tab.resolveProfile(),
            policy: policies.autoplay
        ), tab.resolvedCurrentWebView() != nil else {
            return .notNeeded
        }

        let outcome = webViewReplacement.replaceNormalWebView(
            in: tab,
            targetURL: targetURL ?? tab.url,
            reason: reason
        )
        guard outcome.didReplace else { return outcome }

        tab.publishNavigationStateChangeIfNeeded(
            autoplay.updateRequirement(
                currentURL: tab.url,
                existingWebView: tab.resolvedCurrentWebView(),
                profile: tab.resolveProfile(),
                policy: policies.autoplay
            )
        )
        return outcome
    }
}
