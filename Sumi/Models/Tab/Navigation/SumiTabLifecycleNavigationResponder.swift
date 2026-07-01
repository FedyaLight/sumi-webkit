import Foundation
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
        tab.resetPageSuspensionRuntimeState()
        tab.lifecycleNavigationRuntime.resetRevisitProtection(tab)

        if let url = context.url {
            tab.lifecycleNavigationRuntime.prepareExtensionWebView(
                webView,
                url,
                "SumiTabLifecycleNavigationResponder.willStart"
            )
            if context.action?.navigationType.isBackForward != true {
                tab.lifecycleNavigationRuntime.prepareExtensionRuntimeBeforeCommit(
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
        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

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

        tab.isDisplayingPDFDocument =
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
        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            if tab.pendingMainFrameNavigationKind == .backForward {
                tab.handleNormalTabPermissionNavigation(to: newURL)
            }
            tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: newURL)
            tab.clearSafariContentBlockerReloadRequirementIfResolved(for: newURL)
            tab.clearProtectionReloadRequirementIfResolved(for: newURL)
            tab.clearAutoplayReloadRequirementIfResolved(for: newURL)
            tab.historyRecorder.didCommitMainFrameNavigation(
                to: newURL,
                kind: tab.pendingMainFrameNavigationKind == .backForward ? .backForward : .regular,
                tab: tab
            )
            tab.lifecycleNavigationRuntime.markExtensionEligibleAfterCommit(
                tab,
                "SumiTabLifecycleNavigationResponder.didCommit"
            )
            if tab.pendingMainFrameNavigationKind != .backForward {
                tab.webViewRoutingRuntime.syncTabAcrossWindows(tab.id, webView)
            }
            tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.URL, .loading])
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
        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            tab.lifecycleNavigationRuntime.loadZoomForTab(tab.id)
            tab.refreshFaviconExtensionCache()
            tab.lifecycleNavigationRuntime.applyAdblockZapperRulesAfterNavigation(webView, newURL, tab)
        }

        tab.updateNavigationState()
        let resolvedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if webView.url != nil {
            tab.historyRecorder.updateTitle(resolvedTitle, tab: tab)
        }
        tab.persistenceRuntimeCallbacks.scheduleRuntimeStatePersistence(tab)
        if tab.pendingMainFrameNavigationKind == .backForward {
            tab.finishBackForwardNavigationTracking(using: webView)
            tab.webViewRoutingRuntime.syncTabAcrossWindows(tab.id, webView)
        } else {
            tab.pendingMainFrameNavigationKind = nil
        }

        if tab.audioState.isMuted {
            tab.setMuted(true)
        }

        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .title, .loading]
        )
        tab.mediaRuntimeCallbacks.scheduleBackgroundMediaReconcile("navigation-did-finish")
        tab.lifecycleNavigationRuntime.enforceSiteDataPolicyAfterNavigation(tab)
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
        tab.historyRecorder.didSameDocumentNavigation(
            to: newURL,
            type: navigationType,
            tab: tab
        )
        if tab.pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            tab.persistenceRuntimeCallbacks.scheduleRuntimeStatePersistence(tab)
            tab.webViewRoutingRuntime.syncTabAcrossWindows(tab.id, webView)
            tab.pendingMainFrameNavigationKind = nil
        }

        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.URL])
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
            tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
            return
        }

        guard context?.isCurrent == true else { return }

        tab.loadingState = .didFail(error)
        if !isBackForwardNavigation {
            tab.finishBackForwardNavigationTracking(using: webView)
        }
        tab.updateNavigationState()
        tab.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
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
        return await tab.lifecycleNavigationRuntime.resolveAuthenticationChallenge(
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
        guard tab?.lifecycleNavigationRuntime
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
        tab?.lifecycleNavigationRuntime.finishDestructiveDataCleanupNavigation(webView)
    }
}

private extension WKError {
    var sumiIsNavigationCancelled: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
