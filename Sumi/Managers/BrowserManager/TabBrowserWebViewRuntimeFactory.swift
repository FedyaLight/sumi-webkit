import Foundation
import WebKit

@MainActor
enum TabBrowserWebViewRuntimeFactory {
    static func cleanupRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewCleanupRuntime {
        let runtime = BrowserManagerRuntimeReference(browserManager)
        return .make(
            userscriptsModule: {
                runtime.require().optionalModules.userscripts
            },
            webViewCoordinator: {
                runtime.require().shellRuntime.requireWebViewCoordinator()
            },
            webViewOwnershipService: {
                runtime.require().shellRuntime.requireWebViewOwnershipService()
            }
        )
    }

    static func webKitUIRuntime(
        for browserManager: BrowserManager
    ) -> TabWebKitUIRuntime {
        .make(
            handleWebViewDidClose: { [weak browserManager] webView in
                browserManager?.webViewCloseRouter.handleWebViewDidClose(webView) == true
            },
            saveDownloadedData: { [weak browserManager] data, suggestedFilename, mimeType, originatingURL in
                browserManager?.downloadManager.saveDownloadedData(
                    data,
                    suggestedFilename: suggestedFilename,
                    mimeType: mimeType,
                    originatingURL: originatingURL
                )
            }
        )
    }

    static func replacementRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewReplacementRuntime {
        let runtime = BrowserManagerRuntimeReference(browserManager)
        return .make(
            webViewCoordinator: {
                runtime.require().shellRuntime.requireWebViewCoordinator()
            },
            webViewOwnershipService: {
                runtime.require().shellRuntime.requireWebViewOwnershipService()
            }
        )
    }

    static func configurationContext(
        for browserManager: BrowserManager
    ) -> TabWebViewConfigurationContext {
        .make(
            browserConfiguration: browserManager.browserConfiguration,
            extensionsModule: { [weak browserManager] in
                browserManager?.optionalModules.extensions
            },
            userscriptsModule: { [weak browserManager] in
                browserManager?.optionalModules.userscripts
            },
            boostsModule: { [weak browserManager] in
                browserManager?.optionalModules.boosts
            },
            protectionCoordinator: { [weak browserManager] in
                browserManager?.protectionCoordinator
            }
        )
    }
}

@MainActor
extension TabWebViewReplacementRuntime {
    static func make(
        webViewCoordinator: @escaping () -> WebViewCoordinator,
        webViewOwnershipService: @escaping () -> WebViewOwnershipService
    ) -> Self {
        Self(
            rebuildTrackedWebViews: {
                tab, preferredPrimaryWindowId, targetURL, reason, configuration in
                guard #available(macOS 15.5, *) else {
                    return .failed
                }
                return webViewCoordinator().rebuildService
                    .rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: preferredPrimaryWindowId,
                    load: targetURL,
                    configuration: configuration,
                    reason: reason
                )
            },
            commitUntrackedReplacement: { tab, previous, replacement, reason in
                webViewOwnershipService().replaceDetached(
                    previous,
                    with: replacement,
                    for: tab,
                    reason: reason
                )
            }
        )
    }
}

@MainActor
extension TabWebViewCleanupRuntime {
    static func make(
        userscriptsModule: @escaping () -> SumiUserscriptsModule,
        webViewCoordinator: @escaping () -> WebViewCoordinator,
        webViewOwnershipService: @escaping () -> WebViewOwnershipService
    ) -> Self {
        Self(
            deferProtectedWebViewCleanup: { webView, tabId, reason in
                webViewCoordinator().protectionRuntime.deferCleanup(
                    of: webView,
                    tabID: tabId,
                    reason: reason
                )
            },
            deferWebsiteDataMutationWebViewMaterialization: { tab, replay in
                webViewCoordinator().websiteDataCleanupService
                    .deferWebViewMaterialization(
                    for: tab,
                    replay: replay
                )
            },
            deferWebsiteDataMutationMainFrameSubmission: {
                tab,
                webView,
                semanticRevision,
                replay in
                webViewCoordinator().websiteDataCleanupService
                    .deferMainFrameSubmission(
                    for: tab,
                    on: webView,
                    semanticRevision: semanticRevision,
                    replay: replay
                )
            },
            retireParkedWebView: { tab, webView, reason in
                webViewOwnershipService().releaseParked(
                    webView,
                    for: tab,
                    reason: reason
                )
            },
            cleanupUserScripts: { controller, webViewId in
                userscriptsModule().cleanupWebViewIfLoaded(
                    controller: controller,
                    webViewId: webViewId
                )
            },
            removeWebViewFromContainers: { webView in
                webViewCoordinator().compositorRuntime
                    .removeWebViewFromContainers(webView)
            },
            removeAllWebViews: { tab, closeActiveFullscreenMedia in
                webViewCoordinator().lifecycleService.removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                )
            }
        )
    }
}

@MainActor
extension TabWebKitUIRuntime {
    static func make(
        handleWebViewDidClose: @escaping (WKWebView) -> Bool,
        saveDownloadedData: @escaping (
            _ data: Data,
            _ suggestedFilename: String,
            _ mimeType: String?,
            _ originatingURL: URL
        ) -> Void
    ) -> Self {
        Self(
            handleWebViewDidClose: handleWebViewDidClose,
            saveDownloadedData: saveDownloadedData
        )
    }
}

@MainActor
extension TabWebViewConfigurationContext {
    static func make(
        browserConfiguration: BrowserConfiguration,
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        userscriptsModule: @escaping () -> SumiUserscriptsModule?,
        boostsModule: @escaping () -> SumiBoostsModule?,
        protectionCoordinator: @escaping () -> SumiProtectionCoordinator?
    ) -> Self {
        Self(
            browserConfiguration: browserConfiguration,
            extensionNormalTabUserScripts: {
                extensionsModule()?.normalTabUserScripts() ?? []
            },
            userscriptsNormalTabUserScripts: { url, tabId, profileId, isEphemeral in
                userscriptsModule()?.normalTabUserScripts(
                    for: url,
                    webViewId: tabId,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                ) ?? []
            },
            boostsNormalTabUserScripts: { url, profileId, isEphemeral in
                boostsModule()?.normalTabUserScripts(
                    for: url,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                ) ?? []
            },
            protectionDecision: { url, profileId in
                protectionCoordinator()?.normalTabDecision(
                    for: url,
                    profileId: profileId
                )
            },
            protectionDesiredAttachmentState: { url in
                protectionCoordinator()?.desiredAttachmentState(for: url)
                    ?? .disabled(siteHost: nil)
            },
            safariContentBlockerAttachmentState: { url in
                extensionsModule()?.safariContentBlockerAttachmentState(for: url)
            },
            safariBlockerDesiredAttachmentState: { url in
                extensionsModule()?.safariContentBlockerAttachmentState(for: url)
                    ?? .disabled(siteHost: nil)
            },
            enabledSafariContentBlockingServices: { url, profileId in
                extensionsModule()?.enabledSafariContentBlockingServices(
                    for: url,
                    profileId: profileId
                ) ?? []
            },
            prepareWebViewConfigForExtensionRuntime: { configuration, profileId, reason in
                extensionsModule()?.prepareWebViewConfigForExtensionRuntime(
                    configuration,
                    profileId: profileId,
                    reason: reason
                )
            }
        )
    }
}
