import Foundation
import WebKit

@MainActor
enum TabBrowserWebViewRuntimeFactory {
    static func cleanupRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewCleanupRuntime {
        let webViewRuntime = browserManager.webViewRuntime
        return .make(
            protection: webViewRuntime.protectionRuntime,
            websiteDataCleanup: webViewRuntime.websiteDataCleanupService,
            compositor: webViewRuntime.compositorRuntime,
            lifecycle: webViewRuntime.lifecycleService,
            detachedCleanup: webViewRuntime.detachedWebViewCleanup
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
        let webViewRuntime = browserManager.webViewRuntime
        return .make(
            rebuild: webViewRuntime.rebuildService,
            detachedReplacement: webViewRuntime.detachedWebViewReplacement
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
        rebuild: WebViewRebuildService,
        detachedReplacement: DetachedWebViewReplacementService
    ) -> Self {
        Self(
            rebuildTrackedWebViews: {
                tab, preferredPrimaryWindowId, targetURL, reason, configuration in
                guard #available(macOS 15.5, *) else {
                    return .failed
                }
                return rebuild.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: preferredPrimaryWindowId,
                    load: targetURL,
                    configuration: configuration,
                    reason: reason
                )
            },
            commitUntrackedReplacement: { tab, previous, replacement in
                detachedReplacement.replace(
                    previous,
                    with: replacement,
                    for: tab
                )
            }
        )
    }
}

@MainActor
extension TabWebViewCleanupRuntime {
    static func make(
        protection: WebViewProtectionRuntime,
        websiteDataCleanup: WebsiteDataCleanupService,
        compositor: WebViewCompositorRuntime,
        lifecycle: WebViewLifecycleService,
        detachedCleanup: DetachedWebViewCleanupService
    ) -> Self {
        Self(
            deferProtectedWebViewCleanup: { webView, tabId, reason in
                protection.deferCleanup(
                    of: webView,
                    tabID: tabId,
                    reason: reason
                )
            },
            deferWebsiteDataMutationWebViewMaterialization: { tab, replay in
                websiteDataCleanup.deferWebViewMaterialization(
                    for: tab,
                    replay: replay
                )
            },
            deferWebsiteDataMutationMainFrameSubmission: {
                tab,
                webView,
                semanticRevision,
                replay in
                websiteDataCleanup.deferMainFrameSubmission(
                    for: tab,
                    on: webView,
                    semanticRevision: semanticRevision,
                    replay: replay
                )
            },
            retireParkedWebView: { tab, webView, reason in
                detachedCleanup.releaseParked(
                    webView,
                    for: tab,
                    reason: reason
                )
            },
            removeWebViewFromContainers: { webView in
                compositor.removeWebViewFromContainers(webView)
            },
            removeAllWebViews: { tab, closeActiveFullscreenMedia, intent in
                lifecycle.removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia,
                    intent: intent
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
        boostsModule: @escaping () -> SumiBoostsModule?,
        protectionCoordinator: @escaping () -> SumiProtectionCoordinator?
    ) -> Self {
        Self(
            browserConfiguration: browserConfiguration,
            extensionNormalTabUserScripts: {
                extensionsModule()?.normalTabUserScripts() ?? []
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
