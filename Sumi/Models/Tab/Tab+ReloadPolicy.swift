import Foundation
import SumiDomain

extension Tab {
    var isSafariContentBlockerReloadRequired: Bool {
        safariContentBlockerReloadState.isReloadRequired
    }

    var isProtectionReloadRequired: Bool {
        protectionReloadState.isReloadRequired
    }

    var isAutoplayReloadRequired: Bool {
        autoplayReloadState.isReloadRequired
    }

    var safariContentBlockerAppliedAttachmentState:
        SumiSafariContentBlockerAttachmentState? {
        safariContentBlockerReloadState.appliedAttachmentState
    }

    var protectionAppliedAttachmentState:
        SumiProtectionAttachmentState? {
        protectionReloadState.appliedAttachmentState
    }

    func safariBlockerDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        safariContentBlockerReloadState.desiredAttachmentState(
            for: targetURL,
            policy: navigationRuntime.reloadPolicies.safariContentBlockers
        )
    }

    func protectionDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiProtectionAttachmentState {
        protectionReloadState.desiredAttachmentState(
            for: targetURL,
            policy: navigationRuntime.reloadPolicies.protection
        )
    }

    func markProtectionReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?
    ) {
        publishNavigationStateChangeIfNeeded(
            protectionReloadState.markRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                policy: navigationRuntime.reloadPolicies.protection
            )
        )
    }

    func markSafariContentBlockerReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?
    ) {
        publishNavigationStateChangeIfNeeded(
            safariContentBlockerReloadState.markRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                policy: navigationRuntime.reloadPolicies.safariContentBlockers
            )
        )
    }

    public func updateSafariContentBlockerReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            safariContentBlockerReloadState.updateRequirement(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                policy: navigationRuntime.reloadPolicies.safariContentBlockers
            )
        )
    }

    func clearSafariContentBlockerReloadRequirementIfResolved(
        for committedURL: URL
    ) {
        publishNavigationStateChangeIfNeeded(
            safariContentBlockerReloadState.clearIfResolved(
                for: committedURL,
                policy: navigationRuntime.reloadPolicies.safariContentBlockers
            )
        )
    }

    public func updateProtectionReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            protectionReloadState.updateRequirement(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                policy: navigationRuntime.reloadPolicies.protection
            )
        )
    }

    func clearProtectionReloadRequirementIfResolved(
        for committedURL: URL
    ) {
        publishNavigationStateChangeIfNeeded(
            protectionReloadState.clearIfResolved(
                for: committedURL,
                policy: navigationRuntime.reloadPolicies.protection
            )
        )
    }

    func noteProtectionManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?
    ) {
        protectionReloadState.recordManualReloadResult(
            rebuiltForConfigurationPolicy:
                rebuiltForConfigurationPolicy,
            targetURL: targetURL,
            policy: navigationRuntime.reloadPolicies.protection
        )
    }

    func markAutoplayReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?
    ) {
        publishNavigationStateChangeIfNeeded(
            autoplayReloadState.markRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                policy: navigationRuntime.reloadPolicies.autoplay
            )
        )
    }

    public func updateAutoplayReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            autoplayReloadState.updateRequirement(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                policy: navigationRuntime.reloadPolicies.autoplay
            )
        )
    }

    func clearAutoplayReloadRequirementIfResolved(
        for committedURL: URL
    ) {
        _ = committedURL
        publishNavigationStateChangeIfNeeded(
            autoplayReloadState.clearIfResolved(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                policy: navigationRuntime.reloadPolicies.autoplay
            )
        )
    }

    func protectionAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        protectionReloadState.requiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            policy: navigationRuntime.reloadPolicies.protection
        )
    }

    func safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        safariContentBlockerReloadState.requiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            policy: navigationRuntime.reloadPolicies.safariContentBlockers
        )
    }

    func autoplayPolicyRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        autoplayReloadState.requiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile(),
            policy: navigationRuntime.reloadPolicies.autoplay
        )
    }

    func configurationPolicyRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        protectionAttachmentRequiresNormalWebViewRebuild(for: targetURL)
            || safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
                for: targetURL
            )
            || autoplayPolicyRequiresNormalWebViewRebuild(for: targetURL)
    }

    @discardableResult
    func rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        rebuildNormalWebViewForContentBlockingPolicyOutcome(
            targetURL: targetURL,
            reason: reason
        ).didReplace
    }

    func rebuildNormalWebViewForContentBlockingPolicyOutcome(
        targetURL: URL?,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        configurationPolicyRebuildService.rebuildContentBlockingIfNeeded(
            in: self,
            targetURL: targetURL,
            reason: reason,
            policies: navigationRuntime.reloadPolicies,
            safari: safariContentBlockerReloadState,
            protection: protectionReloadState,
            autoplay: autoplayReloadState
        )
    }

    @discardableResult
    func rebuildNormalWebViewForAutoplayIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        rebuildNormalWebViewForAutoplayOutcome(
            targetURL: targetURL,
            reason: reason
        ).didReplace
    }

    func rebuildNormalWebViewForAutoplayOutcome(
        targetURL: URL?,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        configurationPolicyRebuildService.rebuildAutoplayIfNeeded(
            in: self,
            targetURL: targetURL,
            reason: reason,
            policies: navigationRuntime.reloadPolicies,
            autoplay: autoplayReloadState
        )
    }

    @discardableResult
    func rebuildNormalWebViewForConfigurationPolicyIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        rebuildNormalWebViewForConfigurationPolicyOutcome(
            targetURL: targetURL,
            reason: reason
        ).didReplace
    }

    func rebuildNormalWebViewForConfigurationPolicyOutcome(
        targetURL: URL?,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        let contentBlockingOutcome =
            rebuildNormalWebViewForContentBlockingPolicyOutcome(
                targetURL: targetURL,
                reason: "\(reason).contentBlockingPolicy"
            )
        guard contentBlockingOutcome == .notNeeded else {
            return contentBlockingOutcome
        }
        return rebuildNormalWebViewForAutoplayOutcome(
            targetURL: targetURL,
            reason: "\(reason).autoplayPolicy"
        )
    }
}
