import Foundation

extension Tab {
    func safariContentBlockerDesiredAttachmentState(
        for targetURL: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        reloadPolicyStateOwner.safariContentBlockerDesiredAttachmentState(
            for: targetURL,
            runtime: reloadPolicyRuntime
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
            runtime: reloadPolicyRuntime
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
                runtime: reloadPolicyRuntime
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
                runtime: reloadPolicyRuntime
            )
        )
    }

    func updateSafariContentBlockerReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateSafariContentBlockerReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                runtime: reloadPolicyRuntime
            )
        )
    }

    func clearSafariContentBlockerReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearSafariContentBlockerReloadRequirementIfResolved(
                for: committedURL,
                runtime: reloadPolicyRuntime
            )
        )
    }

    func updateProtectionReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateProtectionReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                runtime: reloadPolicyRuntime
            )
        )
    }

    func clearProtectionReloadRequirementIfResolved(for committedURL: URL) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.clearProtectionReloadRequirementIfResolved(
                for: committedURL,
                runtime: reloadPolicyRuntime
            )
        )
    }

    func protectionCurrentTabDiagnostics() -> SumiProtectionCurrentTabDiagnostics? {
        reloadPolicyStateOwner.protectionCurrentTabDiagnostics(
            for: url,
            existingWebView: existingWebView,
            runtime: reloadPolicyRuntime
        )
    }

    func noteProtectionManualReloadResult(
        rebuiltForConfigurationPolicy: Bool,
        targetURL: URL?
    ) {
        reloadPolicyStateOwner.noteProtectionManualReloadResult(
            rebuiltForConfigurationPolicy: rebuiltForConfigurationPolicy,
            targetURL: targetURL,
            runtime: reloadPolicyRuntime
        )
    }

    func markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor changedURL: URL?) {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.markAutoplayReloadRequiredIfNeeded(
                afterChangingPolicyFor: changedURL,
                currentURL: url,
                existingWebView: existingWebView,
                profile: resolveProfile(),
                runtime: reloadPolicyRuntime
            )
        )
    }

    func updateAutoplayReloadRequirementForCurrentSite() {
        publishNavigationStateChangeIfNeeded(
            reloadPolicyStateOwner.updateAutoplayReloadRequirementForCurrentSite(
                currentURL: url,
                existingWebView: existingWebView,
                profile: resolveProfile(),
                runtime: reloadPolicyRuntime
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
                runtime: reloadPolicyRuntime
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
            runtime: reloadPolicyRuntime
        )
    }

    func safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
        for targetURL: URL?
    ) -> Bool {
        reloadPolicyStateOwner.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(
            for: targetURL,
            existingWebView: existingWebView,
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            runtime: reloadPolicyRuntime
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
        reloadPolicyStateOwner.rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
            targetURL: targetURL,
            reason: reason,
            runtime: reloadPolicyRuntime,
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
            runtime: reloadPolicyRuntime,
            context: reloadPolicyWebViewRebuildContext()
        )
    }

    @discardableResult
    func rebuildNormalWebViewForConfigurationPolicyIfNeeded(
        targetURL: URL?,
        reason: String
    ) -> Bool {
        rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
            targetURL: targetURL,
            reason: "\(reason).contentBlockingPolicy"
        )
            || rebuildNormalWebViewForAutoplayIfNeeded(
                targetURL: targetURL,
                reason: "\(reason).autoplayPolicy"
            )
    }

    private func reloadPolicyWebViewRebuildContext() -> TabReloadPolicyWebViewRebuildContext {
        TabReloadPolicyWebViewRebuildContext(
            currentURL: url,
            existingWebView: { self.existingWebView },
            webViewConfigurationOverride: webViewConfigurationOverride,
            isPopupHost: isPopupHost,
            profile: resolveProfile(),
            replacementContext: configurationPolicyWebViewReplacementContext(),
            publishNavigationStateChangeIfNeeded: { didChange in
                self.publishNavigationStateChangeIfNeeded(didChange)
            }
        )
    }

    private func configurationPolicyWebViewReplacementContext() -> TabConfigurationPolicyWebViewReplacementContext {
        TabConfigurationPolicyWebViewReplacementContext(
            tabId: id,
            existingWebView: { self.existingWebView },
            primaryWindowId: primaryWindowId,
            trackedWindowIdContainingWebView: { webView in
                self.browserManager?.webViewCoordinator?.windowID(containing: webView)
            },
            hasTrackedWebViews: { tabId in
                self.browserManager?.webViewCoordinator?.windowIDs(for: tabId).isEmpty == false
            },
            setTrackedWebView: { webView, tabId, windowId in
                self.browserManager?.webViewCoordinator?.setWebView(
                    webView,
                    for: tabId,
                    in: windowId
                )
            },
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
            clearCurrentWebViewOwnership: {
                self.clearCurrentWebViewOwnership()
            },
            replaceUntrackedWebView: { webView in
                self.replaceUntrackedWebView(webView)
            },
            assignWebViewToWindow: { webView, windowId in
                self.assignWebViewToWindow(webView, windowId: windowId)
            },
            refreshWindowAfterWebViewReplacement: { windowId in
                guard let browserManager = self.browserManager,
                      let windowState = browserManager.windowRegistry?.windows[windowId]
                else { return }
                browserManager.refreshCompositor(for: windowState)
            }
        )
    }

    private var reloadPolicyRuntime: TabReloadPolicyRuntime {
        TabReloadPolicyRuntime.live(browserManager: browserManager)
    }
}
