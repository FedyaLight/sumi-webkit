import Foundation

extension Tab {
    func safariContentBlockerDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        reloadPolicyStateOwner.safariContentBlockerDesiredAttachmentState(
            for: targetURL,
            browserManager: browserManager
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
            browserManager: browserManager
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
                existingWebView: existingWebView,
                browserManager: browserManager
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
                existingWebView: existingWebView,
                browserManager: browserManager
            )
        )
    }

    func updateSafariContentBlockerReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateSafariContentBlockerReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                browserManager: browserManager
            )
        )
    }

    func clearSafariContentBlockerReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearSafariContentBlockerReloadRequirementIfResolved(
                for: committedURL,
                browserManager: browserManager
            )
        )
    }

    func updateProtectionReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateProtectionReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                browserManager: browserManager
            )
        )
    }

    func clearProtectionReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearProtectionReloadRequirementIfResolved(
                for: committedURL,
                browserManager: browserManager
            )
        )
    }

    func protectionCurrentTabDiagnostics() -> SumiProtectionCurrentTabDiagnostics? {
        reloadPolicyStateOwner.protectionCurrentTabDiagnostics(
            for: url,
            existingWebView: existingWebView,
            browserManager: browserManager
        )
    }

    func noteProtectionManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?
    ) {
        reloadPolicyStateOwner.noteProtectionManualReloadResult(
            rebuiltForConfigurationPolicy: rebuiltForConfigurationPolicy,
            targetURL: targetURL,
            browserManager: browserManager
        )
    }

    func markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor changedURL: URL?) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.markAutoplayReloadRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: existingWebView,
                profile: resolveProfile(),
                browserManager: browserManager
            )
        )
    }

    func updateAutoplayReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateAutoplayReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                profile: resolveProfile(),
                browserManager: browserManager
            )
        )
    }

    func clearAutoplayReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearAutoplayReloadRequirementIfResolved(
                for: committedURL,
                currentURL: url,
                existingWebView: existingWebView,
                profile: resolveProfile(),
                browserManager: browserManager
            )
        )
    }

    func protectionAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        reloadPolicyStateOwner.protectionAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: existingWebView,
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            browserManager: browserManager
        )
    }

    func autoplayPolicyRequiresNormalWebViewRebuild(for targetURL: URL?) -> Bool {
        reloadPolicyStateOwner.autoplayPolicyRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: existingWebView,
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile()
        )
    }

    @discardableResult
    func rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        reloadPolicyStateOwner.rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
            targetURL: targetURL,
            reason: reason,
            context: reloadPolicyWebViewRebuildContext()
        )
    }

    @discardableResult
    func rebuildNormalWebViewForAutoplayIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        reloadPolicyStateOwner.rebuildNormalWebViewForAutoplayIfNeeded(
            targetURL: targetURL,
            reason: reason,
            context: reloadPolicyWebViewRebuildContext()
        )
    }

    private func reloadPolicyWebViewRebuildContext() -> TabReloadPolicyWebViewRebuildContext {
        TabReloadPolicyWebViewRebuildContext(
            tabId: id,
            currentURL: url,
            existingWebView: { self.existingWebView },
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile(),
            browserManager: browserManager,
            primaryWindowId: primaryWindowId,
            makeNormalTabWebView: { reason in
                self.makeNormalTabWebView(reason: reason)
            },
            invalidateCurrentPermissionPageForWebViewReplacement: { reason in
                self.invalidateCurrentPermissionPageForWebViewReplacement(reason: reason)
            },
            removeTrackedWebViews: {
                self.browserManager?.webViewCoordinator?.removeAllWebViews(for: self) ?? false
            },
            cleanupCloneWebView: { webView in
                self.cleanupCloneWebView(webView)
            },
            clearOwnedWebView: {
                self._webView = nil
            },
            clearPrimaryWindowId: {
                self.primaryWindowId = nil
            },
            assignOwnedWebView: { webView in
                self._webView = webView
            },
            assignWebViewToWindow: { webView, windowId in
                self.assignWebViewToWindow(webView, windowId: windowId)
            },
            publishNavigationStateChangeIfNeeded: { didChange in
                self.publishNavigationStateChangeIfNeeded(didChange)
            }
        )
    }
}
