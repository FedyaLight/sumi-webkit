import Foundation
import SumiWebRuntime
import WebKit

extension Tab {
    func normalWebViewSetupRequest(
        explicitProfile: Profile? = nil
    ) -> TabNormalWebViewSetupRequest {
        let profile = explicitProfile ?? resolveProfile()
        return TabNormalWebViewSetupRequest(
            tabID: id,
            targetURL: url,
            isPopupHost: isPopupHost,
            resolvedProfile: profile
        )
    }

    func normalWebViewCreationAdmissionStage() -> TabNormalWebViewCreationAdmissionStage {
        let cleanupRuntime = navigationRuntime.webViewCleanupRuntime
        return TabNormalWebViewCreationAdmissionStage(
            deferUntilProfileAvailable: { [weak self] in
                self?.profileWebViewCreationGate
                    .deferCreationUntilProfileAvailable() == true
            },
            beginSuspendedRestore: { [weak self] in
                self?.beginSuspendedRestoreIfNeeded()
            },
            finishSuspendedRestore: { [weak self] in
                self?.finishSuspendedRestoreIfNeeded()
            },
            deferMaterialization: { [weak self] replay in
                guard let self else { return false }
                return cleanupRuntime.deferWebsiteDataMutationWebViewMaterialization(
                    self,
                    replay
                )
            },
            replaySetup: { [weak self] registerExtensionRuntime in
                _ = self?.ensureUntrackedNormalWebViewOutcome(
                    reason: "TabNormalWebViewCreationAdmissionStage.replaySetup",
                    registerTabWithExtensionRuntime: registerExtensionRuntime
                )
            }
        )
    }

    func normalWebViewResidenceStage() -> TabNormalWebViewResidenceStage {
        let cleanupRuntime = navigationRuntime.webViewCleanupRuntime
        return TabNormalWebViewResidenceStage(
            currentWebView: { [weak self] in
                self?.resolvedCurrentWebView()
            },
            parkedWebView: { [weak self] in
                self?.resolvedParkedWebView()
            },
            clearParkedWebView: { [weak self] in
                self?.clearParkedExistingWebView()
            },
            retireParkedWebView: { [weak self] webView, reason in
                guard let self else { return false }
                return cleanupRuntime.retireParkedWebView(self, webView, reason)
            },
            cleanupRejectedWebView: { [weak self] webView in
                self?.cleanupCloneWebView(webView)
            }
        )
    }

    func normalWebViewConfigurationStage() -> TabNormalWebViewConfigurationStage {
        let owner = webViewConfigurationOwner
        let policyLedger = configurationPolicyLedger
        let tabID = id
        let context = webViewConfigurationContext()
        return TabNormalWebViewConfigurationStage(
            normalTabUserScripts: { [weak self] targetURL, profileID in
                self?.normalTabUserScriptsProvider(
                    for: targetURL,
                    profileIDOverride: profileID
                ) ?? SumiNormalTabUserScripts(managedUserScripts: [])
            },
            prepareNormalConfiguration: { url, profile, scripts in
                owner.normalTabWebViewConfiguration(
                    for: url,
                    profile: profile,
                    userScriptsProvider: scripts,
                    context: context
                )
            },
            auxiliaryOverrideConfiguration: { profile in
                owner.auxiliaryOverrideConfiguration(
                    for: profile,
                    context: context
                )
            },
            prepareForExtensionRuntime: { configuration, profileID, reason in
                context.prepareWebViewConfigForExtensionRuntime(
                    configuration,
                    profileID,
                    reason
                )
            },
            applyConfigurationOverride: { configuration, profileID in
                owner.applyWebViewConfigurationOverride(
                    configuration,
                    profileId: profileID,
                    context: context
                )
            },
            canReuse: { webView, fallbackURL, profile in
                owner.canReuseAsNormalTabWebView(
                    webView,
                    fallbackURL: fallbackURL,
                    tabId: tabID,
                    profile: profile,
                    context: context,
                    policyLedger: policyLedger
                )
            }
        )
    }

    func normalWebViewPreparationStage() -> TabNormalWebViewPreparationStage {
        let owner = ownedWebViewPreparationOwner
        return TabNormalWebViewPreparationStage(
            prepareCreatedWebView: { webView, currentURL, reason, options in
                owner.prepareCreatedFocusableWebView(
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
                owner.prepareAssignedWebView(webView)
            },
            prepareReusedWebView: { webView in
                owner.prepareReusedOrExternallyCreatedWebView(webView)
            },
            applyNavigationPreferences: { webView in
                owner.applyOwnedWebViewNavPreferences(to: webView)
            }
        )
    }

    func normalWebViewInitialDocumentStage() -> TabNormalWebViewInitialDocumentStage {
        TabNormalWebViewInitialDocumentStage(
            replaceNormalTabUserScripts: { [weak self] controller, targetURL in
                await self?.replaceNormalTabUserScripts(
                    on: controller,
                    for: targetURL
                )
            },
            loadExtensionOwnedInitialURL: { [weak self] webView, targetURL in
                self?.performMainFrameNavigation(on: webView) { resolvedWebView in
                    resolvedWebView.load(
                        WebRuntimeNavigationRequestFactory.navigationRequest(
                            for: targetURL
                        )
                    )
                }
                self?.applyCachedFaviconOrPlaceholder(for: targetURL)
            },
            registerExtensionRuntime: { [weak self] reason in
                guard let self else { return }
                navigationRuntime.normalWebViewExtensionRuntime
                    .registerTabWithExtensionRuntimeIfNeeded(self, reason)
            },
            restoreSuspendedInteractionState: { [weak self] webView in
                guard let data = self?.suspensionState
                    .takeInteractionStateForRestore()
                else {
                    return false
                }
                SumiWebKitPageStateAdapter.restoreInteractionState(
                    data,
                    to: webView
                )
                return true
            },
            scheduleRuntimeHandoff: { [weak self] webView, targetURL, profileID, reason in
                guard let self else { return }
                NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                    tab: self,
                    webView: webView,
                    targetURL: targetURL,
                    profileId: profileID,
                    registrationReason: reason
                )
            }
        )
    }
}
