import Foundation
import WebKit

@MainActor
enum TabBrowserWebViewRuntimeFactory {
    static func cleanupRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewCleanupRuntime {
        .live(
            userscriptsModule: { [weak browserManager] in
                browserManager?.userscriptsModule
            },
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            }
        )
    }

    static func webKitUIRuntime(
        for browserManager: BrowserManager
    ) -> TabWebKitUIRuntime {
        .live(
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
        .live(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.refreshCompositor(for: windowState)
            }
        )
    }

    static func configurationContext(
        for browserManager: BrowserManager
    ) -> TabWebViewConfigurationContext {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            userscriptsModule: { [weak browserManager] in
                browserManager?.userscriptsModule
            },
            boostsModule: { [weak browserManager] in
                browserManager?.boostsModule
            },
            protectionCoordinator: { [weak browserManager] in
                browserManager?.protectionCoordinator
            }
        )
    }
}

@MainActor
extension TabWebViewReplacementRuntime {
    static func live(
        webViewCoordinator: @escaping () -> WebViewCoordinator?,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        refreshCompositor: @escaping (BrowserWindowState) -> Void
    ) -> Self {
        Self(
            trackedWindowIdContainingWebView: { webView in
                webViewCoordinator()?.windowID(containing: webView)
            },
            hasTrackedWebViews: { tabId in
                webViewCoordinator()?.windowIDs(for: tabId).isEmpty == false
            },
            setTrackedWebView: { webView, tabId, windowId in
                webViewCoordinator()?.setWebView(webView, for: tabId, in: windowId)
            },
            removeTrackedWebViews: { tab in
                webViewCoordinator()?.removeAllWebViews(for: tab) ?? false
            },
            refreshWindowAfterWebViewReplacement: { windowId in
                guard let windowState = windowState(windowId) else { return }
                refreshCompositor(windowState)
            }
        )
    }
}

@MainActor
extension TabWebViewCleanupRuntime {
    static func live(
        userscriptsModule: @escaping () -> SumiUserscriptsModule?,
        webViewCoordinator: @escaping () -> WebViewCoordinator?
    ) -> Self {
        Self(
            deferProtectedWebViewCleanup: { webView, tabId, reason in
                webViewCoordinator()?.deferProtectedWebViewCleanup(
                    webView,
                    tabID: tabId,
                    reason: reason
                ) ?? false
            },
            cleanupUserScripts: { controller, webViewId in
                userscriptsModule()?.cleanupWebViewIfLoaded(
                    controller: controller,
                    webViewId: webViewId
                )
            },
            removeWebViewFromContainers: { webView in
                webViewCoordinator()?.removeWebViewFromContainers(webView)
            },
            removeAllWebViews: { tab, closeActiveFullscreenMedia in
                webViewCoordinator()?.removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                ) ?? false
            }
        )
    }
}

@MainActor
extension TabWebKitUIRuntime {
    static func live(
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
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        userscriptsModule: @escaping () -> SumiUserscriptsModule?,
        boostsModule: @escaping () -> SumiBoostsModule?,
        protectionCoordinator: @escaping () -> SumiProtectionCoordinator?
    ) -> Self {
        Self(
            browserConfiguration: .shared,
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
