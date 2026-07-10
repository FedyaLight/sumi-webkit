import Foundation
import SumiDomain

extension Tab {
    func safariBlockerDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        reloadPolicyStateOwner.safariBlockerDesiredAttachmentState(
            for: targetURL,
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func noteSafariContentBlockerAttachmentApplied(
        _ state: SumiSafariContentBlockerAttachmentState
    ) {
        reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(state)
    }

    func protectionDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiProtectionAttachmentState {
        reloadPolicyStateOwner.protectionDesiredAttachmentState(
            for: targetURL,
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func noteProtectionAttachmentApplied(
        _ state: SumiProtectionAttachmentState
    ) {
        reloadPolicyStateOwner.noteProtectionAttachmentApplied(state)
    }

    func markProtectionReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?
    ) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.markProtectionReloadRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func markSafariContentBlockerReloadRequiredIfNeeded(
        afterChangingPolicyFor changedURL: URL?
    ) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.markSafariContentBlockerReloadRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    public func updateSafariContentBlockerReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateSafariContentBlockerReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func clearSafariContentBlockerReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearSafariContentBlockerReloadRequirementIfResolved(
                for: committedURL,
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    public func updateProtectionReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateProtectionReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func clearProtectionReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearProtectionReloadRequirementIfResolved(
                for: committedURL,
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func protectionCurrentTabDiagnostics() -> SumiProtectionCurrentTabDiagnostics? {
        reloadPolicyStateOwner.protectionCurrentTabDiagnostics(
            for: url,
            existingWebView: resolvedCurrentWebView(),
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func noteProtectionManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?
    ) {
        reloadPolicyStateOwner.noteProtectionManualReloadResult(
            rebuiltForConfigurationPolicy: rebuiltForConfigurationPolicy,
            targetURL: targetURL,
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor changedURL: URL?) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.markAutoplayReloadRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    public func updateAutoplayReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateAutoplayReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func clearAutoplayReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearAutoplayReloadRequirementIfResolved(
                for: committedURL,
                currentURL: url,
                existingWebView: resolvedCurrentWebView(),
                profile: resolveProfile(),
                runtime: navigationRuntime.reloadPolicyRuntime
            )
        )
    }

    func protectionAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        reloadPolicyStateOwner.protectionAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        reloadPolicyStateOwner.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func autoplayPolicyRequiresNormalWebViewRebuild(for targetURL: URL?) -> Bool {
        reloadPolicyStateOwner.autoplayPolicyRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: resolvedCurrentWebView(),
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile(),
            runtime: navigationRuntime.reloadPolicyRuntime
        )
    }

    func configurationPolicyRequiresNormalWebViewRebuild(for targetURL: URL?) -> Bool {
        protectionAttachmentRequiresNormalWebViewRebuild(for: targetURL)
            || safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: targetURL)
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
        reloadPolicyStateOwner.rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
            targetURL: targetURL,
            reason: reason,
            runtime: navigationRuntime.reloadPolicyRuntime,
            context: reloadPolicyWebViewRebuildContext()
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
        reloadPolicyStateOwner.rebuildNormalWebViewForAutoplayIfNeeded(
            targetURL: targetURL,
            reason: reason,
            runtime: navigationRuntime.reloadPolicyRuntime,
            context: reloadPolicyWebViewRebuildContext()
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
        let contentBlockingOutcome = rebuildNormalWebViewForContentBlockingPolicyOutcome(
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

    private func reloadPolicyWebViewRebuildContext() -> TabReloadPolicyWebViewRebuildContext {
        TabReloadPolicyWebViewRebuildContext(
            currentURL: url,
            existingWebView: { self.resolvedCurrentWebView() },
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile(),
            replacementContext: webViewReplacementContextOwner.makeContext(for: self),
            publishNavigationStateChangeIfNeeded: { didChange in
                self.publishNavigationStateChangeIfNeeded(didChange)
            }
        )
    }
}
