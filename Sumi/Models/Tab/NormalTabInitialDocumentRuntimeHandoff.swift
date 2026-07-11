import Foundation
import WebKit
import SumiWebRuntime

@MainActor
enum NormalTabInitialDocumentRuntimeHandoff {
    struct ReplacementBinding {
        let token: WebViewReplacementBindingToken
        let markBound: @MainActor (
            WebViewReplacementBindingToken,
            WebViewReplacementNavigationBinding
        ) -> WebViewReplacementBindingAcceptance
        let fail: @MainActor (
            WebViewReplacementBindingToken,
            WebViewReplacementBindingFailureReason
        ) -> Void
    }

    static func perform(
        waitForInitialUserContent: @MainActor () async -> Void,
        warmInitialDocumentContexts: @MainActor () async -> Void,
        isStillValid: @MainActor () -> Bool,
        register: @MainActor () -> Void,
        load: @MainActor () -> Void
    ) async {
        await waitForInitialUserContent()
        guard isStillValid() else { return }
        await warmInitialDocumentContexts()
        guard isStillValid() else { return }
        register()
        load()
    }

    static func scheduleTabSetupInitialLoad(
        tab: Tab,
        webView: WKWebView?,
        targetURL: URL,
        profileId: UUID?,
        registrationReason: String,
        replacementBinding: ReplacementBinding? = nil
    ) {
        guard let webView else { return }
        scheduleInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: profileId,
            registrationReason: registrationReason,
            expectedResidence: .untracked(tabID: tab.id),
            updatesTabPresentation: true,
            replacementBinding: replacementBinding
        )
    }

    static func scheduleTrackedInitialLoad(
        tab: Tab,
        webView: WKWebView,
        targetURL: URL,
        expectedOwner: TrackedWebViewOwner,
        profileId: UUID?,
        registrationReason: String,
        updatesTabPresentation: Bool,
        replacementBinding: ReplacementBinding? = nil
    ) {
        precondition(
            expectedOwner.tabID == tab.id,
            "Tracked initial load owner must belong to the scheduled tab"
        )
        scheduleInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: profileId,
            registrationReason: registrationReason,
            expectedResidence: .window(expectedOwner),
            updatesTabPresentation: updatesTabPresentation,
            replacementBinding: replacementBinding
        )
    }

    private static func scheduleInitialLoad(
        tab: Tab,
        webView: WKWebView,
        targetURL: URL,
        profileId: UUID?,
        registrationReason: String,
        expectedResidence: WebViewResidence,
        updatesTabPresentation: Bool,
        replacementBinding: ReplacementBinding?
    ) {
        guard let navigationIntent = tab.mainFrameLoads.currentIntent(
            matching: targetURL
        ), tab.webViewSession.residence(of: webView) == expectedResidence,
           let preparationTicket = tab.mainFrameLoads.beginPreparedLoad(
               on: webView,
               intent: navigationIntent
           ) else {
            fail(replacementBinding, reason: .missingPreparation)
            return
        }
        if let replacementBinding {
            precondition(
                replacementBinding.token.webViewID == ObjectIdentifier(webView),
                "Replacement binding token must identify the scheduled WebView"
            )
            precondition(
                replacementBinding.token.semanticRevision == navigationIntent.revision,
                "Replacement binding token must identify the scheduled semantic revision"
            )
        }

        let controller = webView.configuration.userContentController
            .sumiNormalTabUserContentController

        Task { @MainActor [weak tab, weak webView] in
            defer {
                if let tab {
                    tab.mainFrameLoads.finishPreparedLoad(preparationTicket)
                }
            }
            guard Task.isCancelled == false else {
                fail(replacementBinding, reason: .cancelled)
                return
            }
            await perform {
                await waitForInitialUserContentInstallationIfNeeded(controller)
            } warmInitialDocumentContexts: {
                await Self.warmInitialDocumentContextsIfNeeded(
                    tab: tab,
                    profileId: profileId
                )
            } isStillValid: {
                Self.isStillValid(
                    tab: tab,
                    webView: webView,
                    intentRevision: navigationIntent.revision,
                    expectedResidence: expectedResidence
                )
            } register: {
                tab?.registerTabWithExtensionRuntimeIfNeeded(
                    reason: registrationReason
                )
            } load: {
                guard let tab,
                      let webView,
                      Self.isStillValid(
                          tab: tab,
                          webView: webView,
                          intentRevision: navigationIntent.revision,
                          expectedResidence: expectedResidence
                      ) else {
                    fail(replacementBinding, reason: .stale)
                    return
                }
                let outcome = tab.performMainFrameNavigation(
                    on: webView,
                    didSubmit: { navigationID, navigationLifetime in
                        guard let replacementBinding else { return }
                        _ = replacementBinding.markBound(
                            replacementBinding.token,
                            WebViewReplacementNavigationBinding(
                                webView: webView,
                                semanticRevision: navigationIntent.revision,
                                navigationID: navigationID,
                                navigationLifetime: navigationLifetime
                            )
                        )
                    }
                ) { resolvedWebView in
                    guard !resolvedWebView.isLoading,
                          resolvedWebView.url == nil,
                          resolvedWebView === webView,
                          let currentIntent = tab.mainFrameLoads.currentIntent(
                              revision: navigationIntent.revision
                          ),
                          Self.isStillValid(
                              tab: tab,
                              webView: resolvedWebView,
                              intentRevision: navigationIntent.revision,
                              expectedResidence: expectedResidence
                          ) else {
                        return nil
                    }
                    if updatesTabPresentation {
                        tab.beginLoadingPresentationIfNeeded()
                        tab.resetPlaybackActivity()
                        tab.applyCachedFaviconOrPlaceholder(for: currentIntent.targetURL)
                    }
                    return Self.load(currentIntent.targetURL, on: resolvedWebView)
                }
                switch outcome {
                case .submitted:
                    break
                case .alreadyScheduled:
                    fail(replacementBinding, reason: .alreadyScheduled)
                case .missingNavigator:
                    fail(replacementBinding, reason: .missingNavigator)
                case .submissionFailed:
                    fail(replacementBinding, reason: .submissionFailed)
                }
            }

            if Task.isCancelled {
                fail(replacementBinding, reason: .cancelled)
            } else if Self.isStillValid(
                tab: tab,
                webView: webView,
                intentRevision: navigationIntent.revision,
                expectedResidence: expectedResidence
            ) == false {
                fail(replacementBinding, reason: .stale)
            }
        }
    }

    private static func fail(
        _ replacementBinding: ReplacementBinding?,
        reason: WebViewReplacementBindingFailureReason
    ) {
        guard let replacementBinding else { return }
        replacementBinding.fail(replacementBinding.token, reason)
    }

    private static func isStillValid(
        tab: Tab?,
        webView: WKWebView?,
        intentRevision: UInt64,
        expectedResidence: WebViewResidence
    ) -> Bool {
        guard let tab, let webView else { return false }
        return tab.mainFrameLoads.currentIntent.revision == intentRevision
            && isCompatibleResidence(
                tab.webViewSession.residence(of: webView),
                withScheduledResidence: expectedResidence
            )
    }

    private static func isCompatibleResidence(
        _ currentResidence: WebViewResidence?,
        withScheduledResidence scheduledResidence: WebViewResidence
    ) -> Bool {
        switch (scheduledResidence, currentResidence) {
        case let (.untracked(scheduledTabID), .untracked(currentTabID)):
            return currentTabID == scheduledTabID
        case let (.untracked(scheduledTabID), .window(currentOwner)):
            return currentOwner.tabID == scheduledTabID
        default:
            return currentResidence == scheduledResidence
        }
    }

    private static func load(_ targetURL: URL, on webView: WKWebView) -> WKNavigation? {
        WebRuntimeMainFrameLoader.load(targetURL, on: webView)
    }

    private static func waitForInitialUserContentInstallationIfNeeded(
        _ controller: SumiNormalTabUserContentControlling?
    ) async {
        if let controller,
           controller.hasInstalledInitialUserContent == false {
            await controller.waitForInitialUserContentInstallation()
        }
    }

    private static func warmInitialDocumentContextsIfNeeded(
        tab: Tab?,
        profileId: UUID?
    ) async {
        if let profileId, let tab {
            await tab.navigationRuntime.normalWebViewExtensionRuntime
                .ensureInitialExtensionContextsIfNeeded(profileId)
        }
    }
}
