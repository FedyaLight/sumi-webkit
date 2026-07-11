import Foundation
import WebKit

@MainActor
final class TabNormalWebViewRuntimeContextOwner {
    private unowned let tab: Tab

    init(tab: Tab) {
        self.tab = tab
    }

    func makeContext() -> TabNormalWebViewRuntimeContext {
        let tab = tab
        let tabId = tab.id
        let webViewConfigurationOwner = tab.webViewConfigurationOwner
        let configurationPolicyLedger = tab.configurationPolicyLedger
        let ownedWebViewPreparationOwner = tab.ownedWebViewPreparationOwner
        return TabNormalWebViewRuntimeContext(
            tabId: tabId,
            currentURL: { [weak tab, initialURL = tab.url] in
                tab?.url ?? initialURL
            },
            isPopupHost: { [weak tab] in
                tab?.isPopupHost ?? false
            },
            currentWebView: { [weak tab] in
                tab?.resolvedCurrentWebView()
            },
            parkedWebView: { [weak tab] in
                tab?.resolvedParkedWebView()
            },
            profileId: { [weak tab, initialProfileId = tab.profileId] in
                tab?.profileId ?? initialProfileId
            },
            resolveProfile: { [weak tab] in
                tab?.resolveProfile()
            },
            deferWebViewUntilProfileAvailable: { [weak tab] in
                tab?.profileWebViewCreationGate
                    .deferCreationUntilProfileAvailable() == true
            },
            beginSuspendedRestoreIfNeeded: { [weak tab] in
                tab?.beginSuspendedRestoreIfNeeded()
            },
            finishSuspendedRestoreIfNeeded: { [weak tab] in
                tab?.finishSuspendedRestoreIfNeeded()
            },
            setupWebView: { [weak tab] in
                _ = tab?.ensureUntrackedNormalWebView(reason: "TabNormalWebViewRuntimeContext.setupWebView")
            },
            deferWebsiteDataMutationWebViewMaterialization: { [weak tab] replay in
                guard let tab else { return false }
                return tab.navigationRuntime.webViewCleanupRuntime
                    .deferWebsiteDataMutationWebViewMaterialization(tab, replay)
            },
            adoptParkedWebViewAsCurrent: { [weak tab] webView in
                tab?.adoptParkedWebViewAsCurrent(webView)
            },
            clearParkedExistingWebView: { [weak tab] in
                tab?.clearParkedExistingWebView()
            },
            retireParkedWebView: { [weak tab] webView, reason in
                guard let tab else { return false }
                return tab.navigationRuntime.webViewCleanupRuntime.retireParkedWebView(
                    tab,
                    webView,
                    reason
                )
            },
            replaceUntrackedWebView: { [weak tab] webView in
                tab?.replaceUntrackedWebView(webView)
            },
            cleanupCloneWebView: { [weak tab] webView in
                tab?.cleanupCloneWebView(webView)
            },
            configurationContext: { [weak tab] in
                tab?.webViewConfigurationContext() ?? .empty
            },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { url, profile, userScriptsProvider, context in
                    webViewConfigurationOwner.normalTabWebViewConfiguration(
                        for: url,
                        profile: profile,
                        userScriptsProvider: userScriptsProvider,
                        context: context
                    )
                },
                auxiliaryOverrideConfiguration: { profile, context in
                    webViewConfigurationOwner.auxiliaryOverrideConfiguration(
                        for: profile,
                        context: context
                    )
                },
                applyWebViewConfigurationOverride: { configuration, profileId, context in
                    webViewConfigurationOwner.applyWebViewConfigurationOverride(
                        configuration,
                        profileId: profileId,
                        context: context
                    )
                },
                canReuseAsNormalTabWebView: { webView, fallbackURL, profile, context in
                    webViewConfigurationOwner.canReuseAsNormalTabWebView(
                        webView,
                        fallbackURL: fallbackURL,
                        tabId: tabId,
                        profile: profile,
                        context: context,
                        policyLedger: configurationPolicyLedger
                    )
                }
            ),
            preparationRuntime: TabNormalWebViewPreparationRuntime(
                prepareCreatedFocusableWebView: { webView, currentURL, reason, options in
                    ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
                        webView,
                        currentURL: currentURL,
                        reason: reason,
                        enableVisitedLinkRecording: options.enableVisitedLinkRecording,
                        applyNavigationPreferences: options.applyNavigationPreferences,
                        installFaviconRuntime: options.installFaviconRuntime,
                        prepareExtensionRuntime: options.prepareExtensionRuntime
                    )
                },
                prepareAssignedWebView: { webView in
                    ownedWebViewPreparationOwner.prepareAssignedWebView(webView)
                },
                prepareReusedOrExternallyCreatedWebView: { webView in
                    ownedWebViewPreparationOwner.prepareReusedOrExternallyCreatedWebView(webView)
                },
                applyOwnedWebViewNavPreferences: { webView in
                    ownedWebViewPreparationOwner.applyOwnedWebViewNavPreferences(to: webView)
                }
            ),
            normalTabUserScriptsProvider: { [weak tab] targetURL, profileID in
                tab?.normalTabUserScriptsProvider(
                    for: targetURL,
                    profileIDOverride: profileID
                )
                    ?? SumiNormalTabUserScripts(managedUserScripts: [])
            },
            replaceNormalTabUserScripts: { [weak tab] userContentController, targetURL in
                guard let tab else { return }
                await tab.replaceNormalTabUserScripts(
                    on: userContentController,
                    for: targetURL
                )
            },
            loadMainFrameRequest: { [weak tab] webView, request in
                tab?.performMainFrameNavigation(on: webView) { resolvedWebView in
                    resolvedWebView.load(request)
                }
            },
            applyCachedFaviconOrPlaceholder: { [weak tab] url in
                tab?.applyCachedFaviconOrPlaceholder(for: url)
            },
            registerTabWithExtensionRuntimeIfNeeded: { [weak tab] reason in
                guard let tab else { return }
                tab.navigationRuntime.normalWebViewExtensionRuntime.registerTabWithExtensionRuntimeIfNeeded(
                    tab,
                    reason
                )
            },
            scheduleInitialDocumentRuntimeHandoff: { [weak tab] webView, targetURL, profileId, registrationReason in
                guard let tab else { return }
                NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                    tab: tab,
                    webView: webView,
                    targetURL: targetURL,
                    profileId: profileId,
                    registrationReason: registrationReason
                )
            }
        )
    }
}
