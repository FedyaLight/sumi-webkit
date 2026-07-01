import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
extension BrowserManager {
    func makeTabBrowserRuntime() -> TabBrowserRuntime {
        TabBrowserRuntime(
            webViewRoutingRuntime: .live(webViewRoutingService: webViewRoutingService),
            persistenceRuntimeCallbacks: .live(tabManager: tabManager),
            mediaRuntimeCallbacks: .live(
                nowPlayingController: nativeNowPlayingController,
                backgroundMediaOptimizationService: backgroundMediaOptimizationService
            ),
            navigationCommandRuntime: .live(settings: { [weak self] in
                self?.sumiSettings
            }),
            profileResolutionRuntime: .live(
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
            ),
            reloadPolicyRuntime: .live(
                extensionsModule: { [weak self] in
                    self?.extensionsModule
                },
                protectionCoordinator: { [weak self] in
                    self?.protectionCoordinator
                },
                runtimePermissionController: { [weak self] in
                    self?.runtimePermissionController
                }
            ),
            historySwipeRuntime: .live(
                webViewCoordinator: { [weak self] in
                    self?.webViewCoordinator
                },
                cancelWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                    self?.cancelWindowMutationsAfterHistorySwipe(in: windowId)
                },
                flushWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                    self?.flushWindowMutationsAfterHistorySwipe(in: windowId)
                }
            ),
            historyRecordingRuntime: .live(
                historyManager: { [weak self] in
                    self?.historyManager
                },
                currentProfileId: { [weak self] in
                    self?.currentProfile?.id
                }
            ),
            findInPageRuntime: .live(
                webView: { [weak self] tabId, windowId in
                    self?.getWebView(for: tabId, in: windowId)
                }
            ),
            extensionPropertiesRuntime: .live(extensionsModule: { [weak self] in
                self?.extensionsModule
            }),
            closeLifecycleRuntime: .live(
                cleanupZoomForTab: { [weak self] tabId in
                    self?.cleanupZoomForTab(tabId)
                },
                updateTabVisibility: { [weak self] in
                    self?.compositorManager.updateTabVisibility()
                },
                removeTab: { [weak self] tabId in
                    self?.tabManager.removeTab(tabId)
                }
            ),
            lifecycleNavigationRuntime: .live(
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
            ),
            permissionRuntime: .live(
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
            ),
            webViewCleanupRuntime: .live(
                userscriptsModule: { [weak self] in
                    self?.userscriptsModule
                },
                webViewCoordinator: { [weak self] in
                    self?.webViewCoordinator
                }
            ),
            normalWebViewExtensionRuntime: .live(
                extensionsModule: { [weak self] in
                    self?.extensionsModule
                },
                windowState: { [weak self] windowId in
                    self?.windowRegistry?.windows[windowId]
                },
                currentTab: { [weak self] windowState in
                    self?.currentTab(for: windowState)
                }
            ),
            scriptMessageRuntime: .live(glanceManager: glanceManager),
            navigationDelegateRuntime: .live(
                externalSchemePermissionBridge: { [weak self] in
                    self?.externalSchemePermissionBridge
                },
                downloadManager: { [weak self] in
                    self?.downloadManager
                }
            ),
            faviconExtensionRuntime: .live(
                extensionsModule: { [weak self] in
                    self?.extensionsModule
                },
                extensionSurfaceStore: { [weak self] in
                    self?.extensionSurfaceStore
                }
            ),
            popupHandlingRuntime: .live(
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
                    guard let tabManager = self?.tabManager else { return nil }
                    return TabPopupHandlingRuntime.targetSpace(
                        for: openerTab,
                        tabManager: tabManager
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
            ),
            installNavigationRuntime: .live(userscriptsModule: { [weak self] in
                self?.userscriptsModule
            }),
            webKitUIRuntime: .live(
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
            ),
            configurationPolicyWebViewReplacementRuntime: .live(
                webViewCoordinator: { [weak self] in
                    self?.webViewCoordinator
                },
                windowState: { [weak self] windowId in
                    self?.windowRegistry?.windows[windowId]
                },
                refreshCompositor: { [weak self] windowState in
                    self?.refreshCompositor(for: windowState)
                }
            ),
            webViewConfigurationContext: { [weak self] in
                guard let self else { return .empty }
                return .live(
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
            },
            dataServices: { [weak self] in
                guard let dataServices = self?.dataServices else { return nil }
                return TabDependencyDataServices(
                    faviconService: dataServices.faviconService,
                    faviconImageService: dataServices.faviconImageService,
                    visitedLinkStore: dataServices.visitedLinkStore
                )
            },
            currentProfileUpdates: { [weak self] in
                self?.$currentProfile.eraseToAnyPublisher()
            },
            settings: { [weak self] in
                self?.sumiSettings
            },
            hasBrowserRuntime: { [weak self] in
                self != nil
            },
            webPageMenuAppearance: { [weak self] tab, fallback in
                guard let self,
                      let windowState = windowState(containing: tab),
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
                guard let self,
                      let url = request.url
                else { return }

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
            },
            openURLInForegroundTab: { [weak self] url, tab in
                guard let self,
                      let windowState = windowState(containing: tab)
                else { return }

                _ = openNewTab(
                    url: url.absoluteString,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: tab.spaceId
                    )
                )
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
                guard let self else { return false }
                guard let windowState = windowState(containing: tab) else { return false }
                return currentTab(for: windowState)?.id == tab.id
            },
            activate: { [weak self] tab in
                self?.tabManager.setActiveTab(tab)
            }
        )
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
extension TabConfigurationPolicyWebViewReplacementRuntime {
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
    static func live(
        tabSuspensionService: @escaping () -> TabSuspensionService?,
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        loadZoomForTab: @escaping (UUID) -> Void,
        adBlockingModule: @escaping () -> SumiAdBlockingModule?,
        enforceSiteDataPolicyAfterNavigation: @escaping (Tab) -> Void,
        authenticationManager: @escaping () -> AuthenticationManager?,
        webViewCoordinator: @escaping () -> WebViewCoordinator?
    ) -> Self {
        Self(
            resetRevisitProtection: { tab in
                tabSuspensionService()?.resetRevisitProtection(for: tab)
            },
            prepareExtensionWebView: { webView, url, reason in
                extensionsModule()?.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: url,
                    reason: reason
                )
            },
            prepareExtensionRuntimeBeforeCommit: { tab, url, reason in
                extensionsModule()?
                    .prepareExtensionRuntimeBeforeCommittedMainFrameNavigationIfLoaded(
                        tab,
                        destinationURL: url,
                        reason: reason
                    )
            },
            markExtensionEligibleAfterCommit: { tab, reason in
                extensionsModule()?.markTabEligibleAfterCommittedNavigationIfLoaded(
                    tab,
                    reason: reason
                )
            },
            loadZoomForTab: loadZoomForTab,
            applyAdblockZapperRulesAfterNavigation: { webView, url in
                if let policy = adBlockingModule()?.effectivePolicy(for: url),
                   let host = policy.host,
                   policy.isEnabled {
                    SumiAdblockZapperInjector.applySavedRules(to: webView, host: host)
                } else {
                    SumiAdblockZapperInjector.clearAppliedRules(to: webView)
                }
            },
            enforceSiteDataPolicyAfterNavigation: enforceSiteDataPolicyAfterNavigation,
            resolveAuthenticationChallenge: { challenge, tab in
                guard let authenticationManager = authenticationManager() else {
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
            isPreparingForDestructiveDataCleanupNavigation: { webView in
                webViewCoordinator()?
                    .isPreparingForDestructiveDataCleanupNavigation(on: webView) == true
            },
            finishDestructiveDataCleanupNavigation: { webView in
                webViewCoordinator()?.finishDestructiveDataCleanupNavigation(on: webView)
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
            registerNormalTabWithExtensionRuntimeIfNeeded: { tab, reason in
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
            ensureInitialDocumentExtensionContextsLoadedIfNeeded: { profileId in
                await extensionsModule()?
                    .ensureInitialDocumentExtensionContextsLoadedIfNeeded(
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
    static func live(
        isAvailable: @escaping () -> Bool,
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        popupPermissionBridge: @escaping () -> SumiPopupPermissionBridge?,
        targetSpaceForOpener: @escaping (Tab) -> Space?,
        createNewTab: @escaping (_ url: String, _ space: Space?, _ activate: Bool) -> Tab?,
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void,
        presentWebPopup: @escaping (
            _ configuration: WKWebViewConfiguration,
            _ request: URLRequest,
            _ windowFeatures: WKWindowFeatures,
            _ openerTab: Tab,
            _ isExtensionOriginated: Bool
        ) -> WKWebView?,
        openerProfile: @escaping (Tab) -> Profile?,
        createPopupTab: @escaping (_ openerTab: Tab, _ activate: Bool) -> Tab?,
        windowStateContainingTab: @escaping (Tab) -> BrowserWindowState?,
        selectTab: @escaping (Tab, BrowserWindowState) -> Void
    ) -> Self {
        Self(
            hasBrowserRuntime: isAvailable,
            consumeRecentlyOpenedExtensionTabRequest: { requestURL in
                extensionsModule()?
                    .consumeRecentlyOpenedExtensionTabRequestIfLoaded(for: requestURL) == true
            },
            evaluatePopupPermission: { request, tabContext in
                await popupPermissionBridge()?.evaluate(
                    request,
                    tabContext: tabContext
                )
            },
            evaluatePopupPermissionSynchronouslyForWebKitFallback: { request, tabContext in
                popupPermissionBridge()?.evaluateSynchronouslyForWebKitFallback(
                    request,
                    tabContext: tabContext
                )
            },
            openExtensionExternalTab: { requestURL, openerTab in
                guard isAvailable(),
                      let childTab = createNewTab(
                          requestURL.absoluteString,
                          targetSpaceForOpener(openerTab),
                          true
                      )
                else {
                    return false
                }
                if let windowState = windowStateContainingTab(openerTab) {
                    materializeVisibleTabWebViewIfNeeded(childTab, windowState)
                    selectTab(childTab, windowState)
                }
                if childTab.isUnloaded {
                    childTab.loadWebViewIfNeeded()
                }
                extensionsModule()?.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    childTab,
                    reason: "SumiPopupHandlingNavigationResponder.extensionExternalTab"
                )
                return true
            },
            presentWebPopup: { configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                presentWebPopup(
                    configuration,
                    request,
                    windowFeatures,
                    openerTab,
                    isExtensionOriginated
                )
            },
            applyVisitedLinkStoreToPopupConfiguration: { openerTab, configuration in
                guard let profile = openerProfile(openerTab) else {
                    return
                }
                openerTab.visitedLinkStore.applyStore(
                    to: configuration,
                    for: profile
                )
            },
            createPopupTab: createPopupTab,
            windowStateContainingTab: windowStateContainingTab,
            selectTab: selectTab
        )
    }

    static func targetSpace(
        for openerTab: Tab,
        tabManager: TabManager
    ) -> Space? {
        openerTab.spaceId.flatMap { spaceID in
            tabManager.spaces.first(where: { $0.id == spaceID })
        } ?? tabManager.currentSpace
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
                protectionCoordinator()?.currentTabDiagnostics(
                    for: context.currentURL,
                    appliedState: context.appliedState,
                    reloadRequired: context.reloadRequired,
                    reloadRequiredReason: context.reloadRequiredReason,
                    didManualReloadRebuildWebView: context.didManualReloadRebuildWebView,
                    appliedAfterManualReload: context.appliedAfterManualReload,
                    actualAttachedRuleListIdentifiers: context.actualAttachedRuleListIdentifiers,
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
            safariContentBlockerDesiredAttachmentState: { url in
                extensionsModule()?.safariContentBlockerAttachmentState(for: url)
                    ?? .disabled(siteHost: nil)
            },
            enabledSafariContentBlockingServices: { url, profileId in
                extensionsModule()?.enabledSafariContentBlockingServices(
                    for: url,
                    profileId: profileId
                ) ?? []
            },
            prepareWebViewConfigurationForExtensionRuntime: { configuration, profileId, reason in
                extensionsModule()?.prepareWebViewConfigurationForExtensionRuntime(
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
