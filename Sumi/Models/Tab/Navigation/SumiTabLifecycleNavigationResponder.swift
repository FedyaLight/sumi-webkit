import Foundation
import SumiDomain
import WebKit

@MainActor
final class SumiTabLifecycleNavigationResponder:
    SumiNavigationStartResponding,
    SumiNavigationResponseResponding,
    SumiNavigationCommitResponding,
    SumiNavigationCompletionResponding,
    SumiSameDocumentNavigationResponding,
    SumiNavigationAuthChallengeResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            contextURL: context.url,
            requestURL: context.action?.request.url,
            allowCurrentWebViewURLFallback: true
        ) {
            return
        }

        StartupPerformanceTrace.firstNavigationStarted()

        if context.action?.navigationType.isBackForward == true {
            tab.beginBackForwardNavigationTracking(on: webView)
        } else {
            tab.handleNormalTabPermissionNavigation(to: context.url)
            tab.markRegularMainFrameNavigation(on: webView)
        }
        tab.suspensionStateOwner.resetRuntimeState()
        tab.navigationRuntime.lifecycleNavigationRuntime.resetRevisitProtection(tab)

        if let url = context.url {
            tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionWebView(
                webView,
                url,
                "SumiTabLifecycleNavigationResponder.willStart"
            )
            if context.action?.navigationType.isBackForward != true {
                tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionRuntimeBeforeCommit(
                    tab,
                    url,
                    "SumiTabLifecycleNavigationResponder.willStart"
                )
            }
        }
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            contextURL: context.url,
            requestURL: context.action?.request.url,
            allowCurrentWebViewURLFallback: true
        ) {
            return
        }

        tab.beginLoadingPresentationIfNeeded()
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

        if let newURL = webView.url {
            if newURL.absoluteString != tab.url.absoluteString {
                tab.resetPlaybackActivity()
                tab.url = newURL
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                tab.refreshFaviconExtensionCache()
            } else {
                tab.url = newURL
            }
        }
    }

    func decidePolicy(for response: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        guard let tab,
              response.isForMainFrame
        else { return .next }

        tab.suspensionStateOwner.isDisplayingPDFDocument =
            response.mimeType?.lowercased() == "application/pdf"
        return .next
    }

    func navigationDidCommit(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            contextURL: context.url,
            requestURL: context.action?.request.url,
            allowCurrentWebViewURLFallback: true
        ) {
            return
        }

        StartupPerformanceTrace.firstNavigationCommitted()

        tab.loadingState = .didCommit
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward {
                tab.handleNormalTabPermissionNavigation(to: newURL)
            }
            tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: newURL)
            tab.clearSafariContentBlockerReloadRequirementIfResolved(for: newURL)
            tab.clearProtectionReloadRequirementIfResolved(for: newURL)
            tab.clearAutoplayReloadRequirementIfResolved(for: newURL)
            tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
                to: newURL,
                kind: tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward ? .backForward : .regular,
                tab: tab
            )
            tab.navigationRuntime.lifecycleNavigationRuntime.markExtensionEligibleAfterCommit(
                tab,
                "SumiTabLifecycleNavigationResponder.didCommit"
            )
            if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind != .backForward {
                tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(tab.id, webView)
            }
            tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.URL, .loading])
        }

        tab.stateChangeEmitter.postNavigationStateDidChange(for: tab)
    }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        guard let tab,
              context?.isMainFrame == true,
              let webView = context?.webView
        else { return }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            contextURL: context?.url,
            requestURL: context?.action?.request.url,
            allowCurrentWebViewURLFallback: true
        ) {
            finishDestructiveDataCleanupSuppression(on: webView)
            return
        }

        StartupPerformanceTrace.firstNavigationFinished()

        tab.loadingState = .didFinish
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            tab.navigationRuntime.lifecycleNavigationRuntime.loadZoomForTab(tab.id)
            tab.refreshFaviconExtensionCache()
            tab.navigationRuntime.lifecycleNavigationRuntime.applyAdblockZapperRulesAfterNavigation(webView, newURL, tab)
        }

        tab.updateNavigationState()
        let resolvedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if webView.url != nil {
            tab.navigationRuntime.historyRecorder.updateTitle(resolvedTitle, tab: tab)
        }
        tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
        if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward {
            tab.finishBackForwardNavigationTracking(using: webView)
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(tab.id, webView)
        } else {
            tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind = nil
        }

        if tab.audioState.isMuted {
            tab.setMuted(true)
        }

        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .title, .loading]
        )
        tab.mediaRuntime.callbacks.scheduleBackgroundMediaReconcile("navigation-did-finish")
        tab.navigationRuntime.lifecycleNavigationRuntime.enforceSiteDataPolicyAfterNavigation(tab)
        SafariExtensionAutofillFillDiagnostics.endInlineUISession(extensionId: nil)
    }

    func navigationDidSameDocumentNavigation(
        type navigationType: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        guard let tab,
              context?.isCurrent == true,
              let webView = context?.webView,
              let newURL = webView.url
        else { return }

        tab.handleSameDocumentNavigation(to: newURL)
        tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: newURL,
            type: navigationType,
            tab: tab
        )
        if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(tab.id, webView)
            tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind = nil
        }

        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.URL])
    }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        guard let tab,
              context?.isMainFrame == true
        else { return }

        let webView = context?.webView
        if let webView, shouldSuppressForDestructiveDataCleanup(
            on: webView,
            contextURL: context?.url,
            requestURL: context?.action?.request.url,
            allowCurrentWebViewURLFallback: false
        ) {
            finishDestructiveDataCleanupSuppression(on: webView)
            return
        }

        let isBackForwardNavigation = context?.action?.navigationType.isBackForward == true
        if isBackForwardNavigation {
            tab.finishBackForwardNavigationTracking(using: webView)
        }

        if error.sumiIsNavigationCancelled {
            if tab.loadingState.isLoading {
                tab.loadingState = .idle
            }
            tab.updateNavigationState()
            tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
            return
        }

        guard context?.isCurrent == true else { return }

        tab.loadingState = .didFail(error)
        if !isBackForwardNavigation {
            tab.finishBackForwardNavigationTracking(using: webView)
        }
        tab.updateNavigationState()
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context _: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        await sumiAuthChallengeDisposition(for: authenticationChallenge)
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge, context: nil)
    }

    private func sumiAuthChallengeDisposition(
        for authenticationChallenge: URLAuthenticationChallenge
    ) async -> SumiAuthChallengeDisposition? {
        guard let tab else { return .next }
        return await tab.navigationRuntime.lifecycleNavigationRuntime.resolveAuthenticationChallenge(
            authenticationChallenge,
            tab
        )
    }

    private func shouldSuppressForDestructiveDataCleanup(
        on webView: WKWebView,
        contextURL: URL?,
        requestURL: URL?,
        allowCurrentWebViewURLFallback: Bool
    ) -> Bool {
        guard tab?.navigationRuntime.lifecycleNavigationRuntime
            .isPreparingForDataCleanupNavigation(webView) == true
        else {
            return false
        }

        if let candidateURL = contextURL ?? requestURL,
           SumiSurface.isEmptyNewTabURL(candidateURL) {
            return true
        }

        guard allowCurrentWebViewURLFallback,
              let currentURL = webView.url
        else {
            return false
        }
        return SumiSurface.isEmptyNewTabURL(currentURL)
    }

    private func finishDestructiveDataCleanupSuppression(on webView: WKWebView) {
        tab?.navigationRuntime.lifecycleNavigationRuntime.finishDestructiveDataCleanupNavigation(webView)
    }
}

private extension WKError {
    var sumiIsNavigationCancelled: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
