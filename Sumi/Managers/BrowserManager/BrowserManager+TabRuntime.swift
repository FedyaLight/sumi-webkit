import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
extension BrowserManager {
    func makeTabBrowserRuntime() -> TabBrowserRuntime {
        TabBrowserRuntime(
            browserActionService: makeTabBrowserActionService(),
            webViewRoutingRuntime: .live(webViewRoutingService: webViewRoutingService),
            persistenceRuntimeCallbacks: .live(tabManager: tabManager),
            mediaRuntimeCallbacks: .live(
                nowPlayingController: nativeNowPlayingController,
                backgroundMediaOptimizationService: backgroundMediaOptimizationService
            ),
            navigationCommandRuntime: makeTabNavigationCommandRuntime(),
            profileResolutionRuntime: makeTabProfileResolutionRuntime(),
            reloadPolicyRuntime: makeTabReloadPolicyRuntime(),
            historySwipeRuntime: makeTabHistorySwipeRuntime(),
            historyRecordingRuntime: makeTabHistoryRecordingRuntime(),
            findInPageRuntime: makeTabFindInPageRuntime(),
            extensionPropertiesRuntime: makeTabExtensionPropertiesRuntime(),
            closeLifecycleRuntime: makeTabCloseLifecycleRuntime(),
            lifecycleNavigationRuntime: makeTabLifecycleNavigationRuntime(),
            permissionRuntime: makeTabPermissionRuntime(),
            webViewCleanupRuntime: makeTabWebViewCleanupRuntime(),
            normalWebViewExtensionRuntime: makeTabNormalWebViewExtensionRuntime(),
            scriptMessageRuntime: .live(glanceManager: glanceManager),
            navigationDelegateRuntime: makeTabNavigationDelegateRuntime(),
            faviconExtensionRuntime: makeTabFaviconExtensionRuntime(),
            popupHandlingRuntime: makeTabPopupHandlingRuntime(),
            installNavigationRuntime: makeTabInstallNavigationRuntime(),
            webKitUIRuntime: makeTabWebKitUIRuntime(),
            webViewReplacementRuntime: makeTabWebViewReplacementRuntime(),
            webViewConfigurationContext: { [weak self] in
                self?.makeTabWebViewConfigurationContext() ?? .empty
            },
            dataServices: { [weak self] in
                self?.makeTabDependencyDataServices()
            },
            currentProfileUpdates: { [weak self] in
                self?.$currentProfile.eraseToAnyPublisher()
            },
            settings: { [weak self] in
                self?.sumiSettings
            }
        )
    }

    private func makeTabNavigationCommandRuntime() -> TabNavigationCommandRuntime {
        .live(settings: { [weak self] in
            self?.sumiSettings
        })
    }

    private func makeTabProfileResolutionRuntime() -> TabProfileResolutionRuntime {
        .live(
            ephemeralProfileForTab: { [weak self] tabId, profileId in
                self?.windowRegistry?.windows.values.first(where: { window in
                    window.ephemeralTabs.contains(where: { $0.id == tabId })
                })?.ephemeralProfile.flatMap { profile in
                    profile.id == profileId ? profile : nil
                }
            },
            profile: { [weak self] profileId in
                self?.profileManager.profiles.first { $0.id == profileId }
            },
            spaceProfile: { [weak self] spaceId in
                guard let self,
                      let space = tabManager.spaces.first(where: { $0.id == spaceId }),
                      let profileId = space.profileId
                else {
                    return nil
                }
                return profileManager.profiles.first { $0.id == profileId }
            },
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            firstProfile: { [weak self] in
                self?.profileManager.profiles.first
            }
        )
    }

    private func makeTabReloadPolicyRuntime() -> TabReloadPolicyRuntime {
        .live(
            extensionsModule: { [weak self] in
                self?.extensionsModule
            },
            protectionCoordinator: { [weak self] in
                self?.protectionCoordinator
            },
            runtimePermissionController: { [weak self] in
                self?.runtimePermissionController
            }
        )
    }

    private func makeTabHistorySwipeRuntime() -> TabHistorySwipeRuntime {
        .live(
            webViewCoordinator: { [weak self] in
                self?.webViewCoordinator
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.cancelWindowMutationsAfterHistorySwipe(in: windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.flushWindowMutationsAfterHistorySwipe(in: windowId)
            }
        )
    }

    private func makeTabHistoryRecordingRuntime() -> TabHistoryRecordingRuntime {
        .live(
            historyManager: { [weak self] in
                self?.historyManager
            },
            currentProfileId: { [weak self] in
                self?.currentProfile?.id
            }
        )
    }

    private func makeTabFindInPageRuntime() -> TabFindInPageRuntime {
        .live(
            webView: { [weak self] tabId, windowId in
                self?.getWebView(for: tabId, in: windowId)
            }
        )
    }

    private func makeTabExtensionPropertiesRuntime() -> TabExtensionPropertiesRuntime {
        .live(extensionsModule: { [weak self] in
            self?.extensionsModule
        })
    }

    private func makeTabCloseLifecycleRuntime() -> TabCloseLifecycleRuntime {
        .live(
            cleanupZoomForTab: { [weak self] tabId in
                self?.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: { [weak self] in
                self?.compositorManager.updateTabVisibility()
            },
            removeTab: { [weak self] tabId in
                self?.tabManager.removeTab(tabId)
            }
        )
    }

    private func makeTabLifecycleNavigationRuntime() -> TabLifecycleNavigationRuntime {
        .live(
            dependencies: TabLifecycleNavigationRuntime.LiveDependencies(
                tabSuspensionService: { [weak self] in
                    self?.tabSuspensionService
                },
                extensionsModule: { [weak self] in
                    self?.extensionsModule
                },
                loadZoomForTab: { [weak self] tabId in
                    self?.loadZoomForTab(tabId)
                },
                adBlockingModule: { [weak self] in
                    self?.adBlockingModule
                },
                enforceSiteDataPolicyAfterNavigation: { [weak self] tab in
                    self?.enforceSiteDataPolicyAfterNavigation(for: tab)
                },
                authenticationManager: { [weak self] in
                    self?.authenticationManager
                },
                webViewCoordinator: { [weak self] in
                    self?.webViewCoordinator
                }
            )
        )
    }

    private func makeTabPermissionRuntime() -> TabPermissionRuntime {
        .live(
            permissionBridges: { [weak self] in
                self?.permissionBridges
            },
            handlePermissionLifecycleEvent: { [weak self] event in
                self?.permissionLifecycleController.handle(event)
            },
            isActiveGlancePreviewSurface: { [weak self] tabId, webView in
                guard let self,
                      let session = glanceManager.currentSession,
                      session.previewTab.id == tabId,
                      session.previewTab.existingWebView === webView,
                      let windowState = windowRegistry?.windows[session.windowId],
                      glanceManager.activeSession(for: windowState)?.id == session.id
                else {
                    return false
                }
                return true
            }
        )
    }

    private func makeTabWebViewCleanupRuntime() -> TabWebViewCleanupRuntime {
        .live(
            userscriptsModule: { [weak self] in
                self?.userscriptsModule
            },
            webViewCoordinator: { [weak self] in
                self?.webViewCoordinator
            }
        )
    }

    private func makeTabNormalWebViewExtensionRuntime() -> TabNormalWebViewExtensionRuntime {
        .live(
            extensionsModule: { [weak self] in
                self?.extensionsModule
            },
            windowState: { [weak self] windowId in
                self?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak self] windowState in
                self?.currentTab(for: windowState)
            }
        )
    }

    private func makeTabNavigationDelegateRuntime() -> TabNavigationDelegateRuntime {
        .live(
            externalSchemePermissionBridge: { [weak self] in
                self?.externalSchemePermissionBridge
            },
            downloadManager: { [weak self] in
                self?.downloadManager
            }
        )
    }

    private func makeTabFaviconExtensionRuntime() -> TabFaviconExtensionRuntime {
        .live(
            extensionsModule: { [weak self] in
                self?.extensionsModule
            },
            extensionSurfaceStore: { [weak self] in
                self?.extensionSurfaceStore
            }
        )
    }

    private func makeTabPopupHandlingRuntime() -> TabPopupHandlingRuntime {
        .live(
            dependencies: TabPopupHandlingRuntime.LiveDependencies(
                isAvailable: { [weak self] in
                    self != nil
                },
                extensionsModule: { [weak self] in
                    self?.extensionsModule
                },
                popupPermissionBridge: { [weak self] in
                    self?.popupPermissionBridge
                },
                targetSpaceForOpener: { [weak self] openerTab in
                    guard let self else { return nil }
                    return TabPopupHandlingRuntime.targetSpace(
                        for: openerTab,
                        tabManager: tabManager,
                        windowState: windowState(containing: openerTab)
                    )
                },
                createNewTab: { [weak self] url, space, activate in
                    self?.tabManager.createNewTab(
                        url: url,
                        in: space,
                        activate: activate
                    )
                },
                materializeVisibleTabWebViewIfNeeded: { [weak self] tab, windowState in
                    self?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
                },
                presentWebPopup: { [weak self] configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                    self?.auxiliaryWindowManager.presentWebPopup(
                        configuration: configuration,
                        request: request,
                        windowFeatures: windowFeatures,
                        openerTab: openerTab,
                        isExtensionOriginated: isExtensionOriginated,
                        shouldActivateApp: true
                    )
                },
                openerProfile: { [weak self] openerTab in
                    guard let self else { return nil }
                    return TabPopupHandlingRuntime.explicitPopupOpenerProfile(
                        for: openerTab,
                        windowRegistry: windowRegistry,
                        profiles: profileManager.profiles,
                        spaces: tabManager.spaces
                    )
                },
                createPopupTab: { [weak self] openerTab, activate in
                    self?.createPopupTab(
                        from: openerTab,
                        activate: activate
                    )
                },
                windowStateContainingTab: { [weak self] tab in
                    self?.windowState(containing: tab)
                },
                selectTab: { [weak self] tab, windowState in
                    self?.selectTab(tab, in: windowState)
                }
            )
        )
    }

    private func makeTabInstallNavigationRuntime() -> TabInstallNavigationRuntime {
        .live(userscriptsModule: { [weak self] in
            self?.userscriptsModule
        })
    }

    private func makeTabWebKitUIRuntime() -> TabWebKitUIRuntime {
        .live(
            handleWebViewDidClose: { [weak self] webView in
                self?.handleWebViewDidClose(webView) == true
            },
            saveDownloadedData: { [weak self] data, suggestedFilename, mimeType, originatingURL in
                self?.downloadManager.saveDownloadedData(
                    data,
                    suggestedFilename: suggestedFilename,
                    mimeType: mimeType,
                    originatingURL: originatingURL
                )
            }
        )
    }

    private func makeTabWebViewReplacementRuntime() -> TabWebViewReplacementRuntime {
        .live(
            webViewCoordinator: { [weak self] in
                self?.webViewCoordinator
            },
            windowState: { [weak self] windowId in
                self?.windowRegistry?.windows[windowId]
            },
            refreshCompositor: { [weak self] windowState in
                self?.refreshCompositor(for: windowState)
            }
        )
    }

    private func makeTabWebViewConfigurationContext() -> TabWebViewConfigurationContext {
        .live(
            extensionsModule: { [weak self] in
                self?.extensionsModule
            },
            userscriptsModule: { [weak self] in
                self?.userscriptsModule
            },
            boostsModule: { [weak self] in
                self?.boostsModule
            },
            protectionCoordinator: { [weak self] in
                self?.protectionCoordinator
            }
        )
    }

    private func makeTabDependencyDataServices() -> TabDependencyDataServices? {
        TabDependencyDataServices(
            faviconService: dataServices.faviconService,
            faviconImageService: dataServices.faviconImageService,
            visitedLinkStore: dataServices.visitedLinkStore
        )
    }

    private func makeTabBrowserActionService() -> TabBrowserActionService {
        TabBrowserActionService(
            hasBrowserRuntime: { [weak self] in
                self != nil
            },
            webPageMenuAppearance: { [weak self] tab, fallback in
                self?.webPageMenuAppearance(for: tab, fallback: fallback) ?? fallback
            },
            canBookmark: { [weak self] tab in
                self?.bookmarkManager.canBookmark(tab) ?? false
            },
            requestBookmarkEditorFromMenu: { [weak self] in
                self?.requestBookmarkEditorForActiveWindowFromMenu()
            },
            canStartContextMenuDownload: { [weak self] in
                self != nil
            },
            startContextMenuDownload: { [weak self] webView, request in
                self?.startContextMenuDownload(webView: webView, request: request)
            },
            openURLInForegroundTab: { [weak self] url, tab in
                self?.openURLInForegroundTab(url, from: tab)
            },
            openURLsInNewWindow: { [weak self] urls in
                self?.openURLsInNewWindow(urls)
            },
            notificationPermissionBridge: { [weak self] in
                self?.notificationPermissionBridge
            },
            shortcutLaunchURL: { [weak self] shortcutPinId in
                self?.tabManager.shortcutPin(by: shortcutPinId)?.launchURL
            },
            reconcileExtensionRuntimeOnUserGesture: { [weak self] tab, reason in
                self?.extensionsModule.reconcileExtensionRuntimeOnUserGestureIfNeeded(
                    tab,
                    reason: reason
                )
            },
            isCurrentTab: { [weak self] tab in
                self?.isCurrentTab(tab) ?? false
            },
            activate: { [weak self] tab in
                self?.tabManager.setActiveTab(tab)
            }
        )
    }

    private func webPageMenuAppearance(for tab: Tab, fallback: NSAppearance?) -> NSAppearance? {
        guard let windowState = windowState(containing: tab),
              let settings = sumiSettings
        else {
            return fallback
        }
        let globalScheme: ColorScheme = fallback?.name == .darkAqua ? .dark : .light
        let themeContext = windowState.resolvedThemeContext(
            global: globalScheme,
            settings: settings
        )
        return NSAppearance.sumiChromeAppearance(
            for: themeContext.nativeSurfaceColorScheme,
            fallback: fallback
        )
    }

    private func startContextMenuDownload(webView: WKWebView, request: URLRequest) {
        guard let url = request.url else { return }

        let callback: @MainActor @Sendable (WKDownload) -> Void = { [weak self] download in
            _ = self?.downloadManager.addDownload(
                download,
                originalURL: url,
                suggestedFilename: DownloadFileUtilities.suggestedFilename(
                    response: nil,
                    requestURL: url,
                    fallback: "download"
                )
            )
        }
        webView.startDownload(using: request, completionHandler: callback)
    }

    private func openURLInForegroundTab(_ url: URL, from tab: Tab) {
        guard let windowState = windowState(containing: tab) else { return }

        _ = openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: tab.spaceId
            )
        )
    }

    private func isCurrentTab(_ tab: Tab) -> Bool {
        guard let windowState = windowState(containing: tab) else { return false }
        return currentTab(for: windowState)?.id == tab.id
    }
}

@MainActor
extension TabWebViewRoutingRuntime {
    static func live(webViewRoutingService: BrowserWebViewRoutingService) -> Self {
        Self(
            syncTabAcrossWindows: { [weak webViewRoutingService] tabId, webView in
                webViewRoutingService?.syncTabAcrossWindows(
                    tabId,
                    originatingWebView: webView
                )
            },
            reloadTabAcrossWindows: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.reloadTabAcrossWindows(tabId)
            },
            setMuteState: { [weak webViewRoutingService] muted, tabId in
                webViewRoutingService?.setMuteState(muted, for: tabId)
            }
        )
    }
}

@MainActor
extension TabRuntimePersistenceCallbacks {
    static func live(tabManager: TabManager) -> Self {
        Self(
            updateNavigationState: { [weak tabManager] tab in
                tabManager?.updateTabNavigationState(tab)
            },
            scheduleRuntimeStatePersistence: { [weak tabManager] tab in
                tabManager?.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }
}

@MainActor
extension TabMediaRuntimeCallbacks {
    static func live(
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling,
        backgroundMediaOptimizationService: SumiBackgroundMediaOptimizationService
    ) -> Self {
        Self(
            scheduleNowPlayingRefresh: { [weak nowPlayingController] delayNanoseconds in
                nowPlayingController?.scheduleRefresh(delayNanoseconds: delayNanoseconds)
            },
            scheduleBackgroundMediaReconcile: { [weak backgroundMediaOptimizationService] reason in
                backgroundMediaOptimizationService?.scheduleReconcile(reason: reason)
            },
            notifyNowPlayingTabUnloaded: { [weak nowPlayingController] tabId in
                nowPlayingController?.handleTabUnloaded(tabId)
                nowPlayingController?.scheduleRefresh(delayNanoseconds: 0)
            }
        )
    }
}

@MainActor
extension TabScriptMessageRuntime {
    static func live(glanceManager: GlanceManager) -> Self {
        Self(
            presentExternalURLInGlance: { [weak glanceManager] url, tab, originRectInWindow in
                glanceManager?.presentExternalURL(
                    url,
                    from: tab,
                    originRectInWindow: originRectInWindow
                )
            }
        )
    }
}

@MainActor
extension TabHistorySwipeRuntime {
    static func live(
        webViewCoordinator: @escaping () -> WebViewCoordinator?,
        cancelWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void,
        flushWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            windowIDContaining: { webView in
                webViewCoordinator()?.windowID(containing: webView)
            },
            beginHistorySwipeProtection: { tabId, webView, originURL, originHistoryItem in
                webViewCoordinator()?.beginHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    originURL: originURL,
                    originHistoryItem: originHistoryItem
                )
            },
            finishHistorySwipeProtection: { tabId, webView, currentURL, currentHistoryItem in
                webViewCoordinator()?.finishHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    currentURL: currentURL,
                    currentHistoryItem: currentHistoryItem
                ) ?? false
            },
            cancelWindowMutationsAfterHistorySwipe: cancelWindowMutationsAfterHistorySwipe,
            flushWindowMutationsAfterHistorySwipe: flushWindowMutationsAfterHistorySwipe
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
extension TabCloseLifecycleRuntime {
    static func live(
        cleanupZoomForTab: @escaping (UUID) -> Void,
        updateTabVisibility: @escaping () -> Void,
        removeTab: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            cleanupZoomForTab: cleanupZoomForTab,
            updateTabVisibility: updateTabVisibility,
            removeTab: removeTab
        )
    }
}

@MainActor
extension TabLifecycleNavigationRuntime {
    struct LiveDependencies {
        let tabSuspensionService: () -> TabSuspensionService?
        let extensionsModule: () -> SumiExtensionsModule?
        let loadZoomForTab: (UUID) -> Void
        let adBlockingModule: () -> SumiAdBlockingModule?
        let enforceSiteDataPolicyAfterNavigation: (Tab) -> Void
        let authenticationManager: () -> AuthenticationManager?
        let webViewCoordinator: () -> WebViewCoordinator?
    }

    static func live(dependencies: LiveDependencies) -> Self {
        Self(
            resetRevisitProtection: { tab in
                dependencies.tabSuspensionService()?.resetRevisitProtection(for: tab)
            },
            prepareExtensionWebView: { webView, url, reason in
                dependencies.extensionsModule()?.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: url,
                    reason: reason
                )
            },
            prepareExtensionRuntimeBeforeCommit: { tab, url, reason in
                dependencies.extensionsModule()?
                    .prepareExtensionRuntimeBeforeCommittedMainFrameNavigationIfLoaded(
                        tab,
                        destinationURL: url,
                        reason: reason
                    )
            },
            markExtensionEligibleAfterCommit: { tab, reason in
                dependencies.extensionsModule()?.markTabEligibleAfterCommittedNavigationIfLoaded(
                    tab,
                    reason: reason
                )
            },
            loadZoomForTab: dependencies.loadZoomForTab,
            applyAdblockZapperRulesAfterNavigation: { webView, url, tab in
                if let policy = dependencies.adBlockingModule()?.effectivePolicy(for: url),
                   let host = policy.host,
                   policy.isEnabled,
                   let profile = tab.resolveProfile() {
                    SumiAdblockZapperInjector.applySavedRules(
                        to: webView,
                        host: host,
                        profilePartitionId: profile.id.uuidString,
                        isEphemeralProfile: profile.isEphemeral
                    )
                } else {
                    SumiAdblockZapperInjector.clearAppliedRules(to: webView)
                }
            },
            enforceSiteDataPolicyAfterNavigation: dependencies.enforceSiteDataPolicyAfterNavigation,
            resolveAuthenticationChallenge: { challenge, tab in
                guard let authenticationManager = dependencies.authenticationManager() else {
                    return .next
                }

                return await withCheckedContinuation { continuation in
                    let handled = authenticationManager.handleAuthenticationChallenge(
                        challenge,
                        for: tab
                    ) { disposition, credential in
                        switch disposition {
                        case .useCredential:
                            if let credential {
                                continuation.resume(returning: .credential(credential))
                            } else {
                                continuation.resume(returning: .next)
                            }
                        case .cancelAuthenticationChallenge:
                            continuation.resume(returning: .cancel)
                        case .rejectProtectionSpace:
                            continuation.resume(returning: .rejectProtectionSpace)
                        default:
                            continuation.resume(returning: .next)
                        }
                    }

                    if !handled {
                        continuation.resume(returning: .next)
                    }
                }
            },
            isPreparingForDataCleanupNavigation: { webView in
                dependencies.webViewCoordinator()?
                    .isPreparingForDataCleanupNavigation(on: webView) == true
            },
            finishDestructiveDataCleanupNavigation: { webView in
                dependencies.webViewCoordinator()?.finishDestructiveDataCleanupNavigation(on: webView)
            }
        )
    }
}

@MainActor
extension TabPermissionRuntime {
    static func live(
        permissionBridges: @escaping () -> BrowserPermissionBridgeRegistry?,
        handlePermissionLifecycleEvent: @escaping (SumiPermissionLifecycleEvent) -> Void,
        isActiveGlancePreviewSurface: @escaping (_ tabId: UUID, _ webView: WKWebView) -> Bool
    ) -> Self {
        Self(
            permissionBridges: permissionBridges,
            handlePermissionLifecycleEvent: handlePermissionLifecycleEvent,
            isActiveGlancePreviewSurface: isActiveGlancePreviewSurface
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
extension TabNormalWebViewExtensionRuntime {
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        currentTab: @escaping (BrowserWindowState) -> Tab?
    ) -> Self {
        Self(
            registerTabWithExtensionRuntimeIfNeeded: { tab, reason in
                guard let extensionsModule = extensionsModule() else { return }

                extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
                    tab,
                    reason: reason
                )

                guard let windowId = tab.primaryWindowId,
                      let windowState = windowState(windowId),
                      currentTab(windowState)?.id == tab.id
                else {
                    return
                }

                extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            },
            prepareWebViewForExtensionRuntime: { webView, currentURL, reason in
                extensionsModule()?.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: currentURL,
                    reason: reason
                )
            },
            ensureInitialExtensionContextsIfNeeded: { profileId in
                await extensionsModule()?
                    .ensureInitialExtensionContextsIfNeeded(
                        profileId: profileId
                    )
            }
        )
    }
}

@MainActor
extension TabNavigationDelegateRuntime {
    static func live(
        externalSchemePermissionBridge: @escaping () -> SumiExternalSchemePermissionBridge?,
        downloadManager: @escaping () -> DownloadManager?
    ) -> Self {
        Self(
            externalSchemePermissionBridge: externalSchemePermissionBridge,
            downloadManager: downloadManager
        )
    }
}

@MainActor
extension TabFaviconExtensionRuntime {
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        extensionSurfaceStore: @escaping () -> BrowserExtensionSurfaceStore?
    ) -> Self {
        Self(
            installedExtensions: {
                extensionsModule()?.managerIfLoadedAndEnabled()?.installedExtensions
                    ?? extensionSurfaceStore()?.installedExtensions
                    ?? []
            }
        )
    }
}

@MainActor
extension TabPopupHandlingRuntime {
    struct LiveDependencies {
        let isAvailable: () -> Bool
        let extensionsModule: () -> SumiExtensionsModule?
        let popupPermissionBridge: () -> SumiPopupPermissionBridge?
        let targetSpaceForOpener: (Tab) -> Space?
        let createNewTab: (_ url: String, _ space: Space?, _ activate: Bool) -> Tab?
        let materializeVisibleTabWebViewIfNeeded: (Tab, BrowserWindowState) -> Void
        let presentWebPopup: (
            _ configuration: WKWebViewConfiguration,
            _ request: URLRequest,
            _ windowFeatures: WKWindowFeatures,
            _ openerTab: Tab,
            _ isExtensionOriginated: Bool
        ) -> WKWebView?
        let openerProfile: (Tab) -> Profile?
        let createPopupTab: (_ openerTab: Tab, _ activate: Bool) -> Tab?
        let windowStateContainingTab: (Tab) -> BrowserWindowState?
        let selectTab: (Tab, BrowserWindowState) -> Void
    }

    static func live(dependencies: LiveDependencies) -> Self {
        Self(
            hasBrowserRuntime: dependencies.isAvailable,
            consumeRecentlyOpenedExtensionTabRequest: { requestURL in
                dependencies.extensionsModule()?
                    .consumeRecentlyOpenedExtensionTabRequestIfLoaded(for: requestURL) == true
            },
            evaluatePopupPermission: { request, tabContext in
                await dependencies.popupPermissionBridge()?.evaluate(
                    request,
                    tabContext: tabContext
                )
            },
            evaluatePopupPermissionForWebKitFallback: { request, tabContext in
                dependencies.popupPermissionBridge()?.evaluateSynchronouslyForWebKitFallback(
                    request,
                    tabContext: tabContext
                )
            },
            openExtensionExternalTab: { requestURL, openerTab in
                guard dependencies.isAvailable(),
                      let childTab = dependencies.createNewTab(
                          requestURL.absoluteString,
                          dependencies.targetSpaceForOpener(openerTab),
                          true
                      )
                else {
                    return false
                }
                if let windowState = dependencies.windowStateContainingTab(openerTab) {
                    dependencies.materializeVisibleTabWebViewIfNeeded(childTab, windowState)
                    dependencies.selectTab(childTab, windowState)
                }
                if childTab.isUnloaded {
                    childTab.loadWebViewIfNeeded()
                }
                dependencies.extensionsModule()?.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    childTab,
                    reason: "SumiPopupHandlingNavigationResponder.extensionExternalTab"
                )
                return true
            },
            presentWebPopup: { configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                dependencies.presentWebPopup(
                    configuration,
                    request,
                    windowFeatures,
                    openerTab,
                    isExtensionOriginated
                )
            },
            applyVisitedLinksToPopupConfiguration: { openerTab, configuration in
                guard let profile = dependencies.openerProfile(openerTab) else {
                    return
                }
                openerTab.visitedLinkStore.applyStore(
                    to: configuration,
                    for: profile
                )
            },
            createPopupTab: dependencies.createPopupTab,
            windowStateContainingTab: dependencies.windowStateContainingTab,
            selectTab: dependencies.selectTab
        )
    }

    static func targetSpace(
        for openerTab: Tab,
        tabManager: TabManager,
        windowState: BrowserWindowState?
    ) -> Space? {
        if let openerSpaceId = openerTab.spaceId,
           let openerSpace = tabManager.spaces.first(where: { $0.id == openerSpaceId }) {
            return openerSpace
        }

        if let windowSpaceId = windowState?.currentSpaceId,
           let windowSpace = tabManager.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let windowProfileId = windowState?.currentProfileId,
           let windowProfileSpace = tabManager.spaces.first(where: { $0.profileId == windowProfileId }) {
            return windowProfileSpace
        }

        if let openerProfileId = openerTab.profileId,
           let openerProfileSpace = tabManager.spaces.first(where: { $0.profileId == openerProfileId }) {
            return openerProfileSpace
        }

        return tabManager.spaces.first
    }

    static func explicitPopupOpenerProfile(
        for tab: Tab,
        windowRegistry: WindowRegistry?,
        profiles: [Profile],
        spaces: [Space]
    ) -> Profile? {
        if let profileId = tab.profileId {
            if let windowState = windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == tab.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == profileId {
                return ephemeralProfile
            }

            return profiles.first { $0.id == profileId }
        }

        if let spaceId = tab.spaceId,
           let space = spaces.first(where: { $0.id == spaceId }),
           let profileId = space.profileId {
            return profiles.first { $0.id == profileId }
        }

        return nil
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
extension TabInstallNavigationRuntime {
    static func live(userscriptsModule: @escaping () -> SumiUserscriptsModule?) -> Self {
        Self(
            interceptInstallNavigation: { url in
                userscriptsModule()?.interceptInstallNavigationIfNeeded(url) == true
            }
        )
    }
}

@MainActor
extension TabReloadPolicyRuntime {
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        protectionCoordinator: @escaping () -> SumiProtectionCoordinator?,
        runtimePermissionController: @escaping () -> (any SumiRuntimePermissionControlling)?
    ) -> Self {
        Self(
            safariContentBlockerAttachmentState: { url in
                extensionsModule()?.safariContentBlockerAttachmentState(for: url)
                    ?? .disabled(siteHost: nil)
            },
            protectionAttachmentState: { url in
                protectionCoordinator()?.desiredAttachmentState(for: url)
                    ?? .disabled(siteHost: nil)
            },
            protectionSurfaceHost: { url in
                protectionCoordinator()?.surfaceEligibility(for: url).normalizedSiteHost
            },
            protectionCurrentTabDiagnostics: { context in
                let actualAttachedOverrideIdentifiers: [String]
                let hasActualAttachedOverride: Bool
                switch context.actualAttachedRuleLists {
                case .deriveFromDiagnostics:
                    actualAttachedOverrideIdentifiers = []
                    hasActualAttachedOverride = false
                case .identifiers(let identifiers):
                    actualAttachedOverrideIdentifiers = identifiers
                    hasActualAttachedOverride = true
                }
                protectionCoordinator()?.currentTabDiagnostics(
                    for: context.currentURL,
                    appliedState: context.appliedState,
                    reloadRequired: context.reloadRequired,
                    reloadRequiredReason: context.reloadRequiredReason,
                    didManualReloadRebuildWebView: context.didManualReloadRebuildWebView,
                    appliedAfterManualReload: context.appliedAfterManualReload,
                    actualAttachedRuleListIdentifiers: hasActualAttachedOverride
                        ? actualAttachedOverrideIdentifiers
                        : nil,
                    contentBlockingAssetSummary: context.contentBlockingAssetSummary,
                    webViewRebuildDuration: context.webViewRebuildDuration,
                    urlHubSummaryDuration: context.urlHubSummaryDuration
                )
            },
            evaluateAutoplayPolicyChange: { requestedState, webView in
                runtimePermissionController()?.evaluateAutoplayPolicyChange(
                    requestedState,
                    for: webView
                ) ?? .noOp
            }
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

@MainActor
extension TabExtensionPropertiesRuntime {
    static func live(extensionsModule: @escaping () -> SumiExtensionsModule?) -> Self {
        Self(
            notifyTabPropertiesChanged: { tab, properties in
                extensionsModule()?.notifyTabPropertiesChangedIfLoaded(
                    tab,
                    properties: properties
                )
            }
        )
    }
}

@MainActor
extension TabFindInPageRuntime {
    static func live(
        webView: @escaping (_ tabId: UUID, _ windowId: UUID) -> WKWebView?
    ) -> Self {
        Self(
            webView: webView
        )
    }
}

@MainActor
extension TabHistoryRecordingRuntime {
    static func live(
        historyManager: @escaping () -> HistoryManager?,
        currentProfileId: @escaping () -> UUID?
    ) -> Self {
        Self(
            updateTitleIfNeeded: { title, url, profileId, isEphemeral in
                historyManager()?.updateTitleIfNeeded(
                    title: title,
                    url: url,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            addVisit: { url, title, timestamp, tabId, profileId, isEphemeral in
                historyManager()?.addVisit(
                    url: url,
                    title: title,
                    timestamp: timestamp,
                    tabId: tabId,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            currentProfileId: currentProfileId
        )
    }
}

@MainActor
extension TabNavigationCommandRuntime {
    static func live(settings: @escaping () -> SumiSettingsService?) -> Self {
        Self(
            resolvedSearchEngineTemplate: {
                settings()?.resolvedSearchEngineTemplate
            }
        )
    }
}

@MainActor
extension TabProfileResolutionRuntime {
    static func live(
        ephemeralProfileForTab: @escaping (_ tabId: UUID, _ profileId: UUID) -> Profile?,
        profile: @escaping (UUID) -> Profile?,
        spaceProfile: @escaping (UUID) -> Profile?,
        currentProfile: @escaping () -> Profile?,
        firstProfile: @escaping () -> Profile?
    ) -> Self {
        Self(
            ephemeralProfileForTab: ephemeralProfileForTab,
            profile: profile,
            spaceProfile: spaceProfile,
            currentProfile: currentProfile,
            firstProfile: firstProfile
        )
    }
}
