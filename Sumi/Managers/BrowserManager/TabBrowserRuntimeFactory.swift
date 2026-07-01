import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

/// Composition root for the per-tab runtime: assembles the `TabBrowserRuntime`
/// handed to each `Tab` from narrowly scoped runtime adapters over browser subsystems.
@MainActor
enum TabBrowserRuntimeFactory {
    static func make(for browserManager: BrowserManager) -> TabBrowserRuntime {
        TabBrowserRuntime(
            browserActionService: makeTabBrowserActionService(for: browserManager),
            webViewRoutingRuntime: .live(webViewRoutingService: browserManager.webViewRoutingService),
            persistenceRuntimeCallbacks: .live(tabManager: browserManager.tabManager),
            mediaRuntimeCallbacks: .live(
                nowPlayingController: browserManager.nativeNowPlayingController,
                backgroundMediaOptimizationService: browserManager.backgroundMediaOptimizationService
            ),
            navigationCommandRuntime: makeTabNavigationCommandRuntime(for: browserManager),
            profileResolutionRuntime: makeTabProfileResolutionRuntime(for: browserManager),
            reloadPolicyRuntime: makeTabReloadPolicyRuntime(for: browserManager),
            historySwipeRuntime: makeTabHistorySwipeRuntime(for: browserManager),
            historyRecordingRuntime: makeTabHistoryRecordingRuntime(for: browserManager),
            findInPageRuntime: makeTabFindInPageRuntime(for: browserManager),
            extensionPropertiesRuntime: makeTabExtensionPropertiesRuntime(for: browserManager),
            closeLifecycleRuntime: makeTabCloseLifecycleRuntime(for: browserManager),
            lifecycleNavigationRuntime: makeTabLifecycleNavigationRuntime(for: browserManager),
            permissionRuntime: makeTabPermissionRuntime(for: browserManager),
            webViewCleanupRuntime: makeTabWebViewCleanupRuntime(for: browserManager),
            normalWebViewExtensionRuntime: makeTabNormalWebViewExtensionRuntime(for: browserManager),
            scriptMessageRuntime: .live(glanceManager: browserManager.glanceManager),
            navigationDelegateRuntime: makeTabNavigationDelegateRuntime(for: browserManager),
            faviconExtensionRuntime: makeTabFaviconExtensionRuntime(for: browserManager),
            popupHandlingRuntime: makeTabPopupHandlingRuntime(for: browserManager),
            installNavigationRuntime: makeTabInstallNavigationRuntime(for: browserManager),
            webKitUIRuntime: makeTabWebKitUIRuntime(for: browserManager),
            webViewReplacementRuntime: makeTabWebViewReplacementRuntime(for: browserManager),
            webViewConfigurationContext: { [weak browserManager] in
                browserManager.map { Self.makeTabWebViewConfigurationContext(for: $0) } ?? .empty
            },
            dataServices: { [weak browserManager] in
                browserManager.flatMap { Self.makeTabDependencyDataServices(for: $0) }
            },
            currentProfileUpdates: { [weak browserManager] in
                browserManager?.$currentProfile.eraseToAnyPublisher()
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }

    private static func makeTabNavigationCommandRuntime(
        for browserManager: BrowserManager
    ) -> TabNavigationCommandRuntime {
        .live(settings: { [weak browserManager] in
            browserManager?.sumiSettings
        })
    }

    private static func makeTabProfileResolutionRuntime(
        for browserManager: BrowserManager
    ) -> TabProfileResolutionRuntime {
        .live(
            ephemeralProfileForTab: { [weak browserManager] tabId, profileId in
                browserManager?.windowRegistry?.windows.values.first(where: { window in
                    window.ephemeralTabs.contains(where: { $0.id == tabId })
                })?.ephemeralProfile.flatMap { profile in
                    profile.id == profileId ? profile : nil
                }
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            spaceProfile: { [weak browserManager] spaceId in
                guard let browserManager,
                      let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }),
                      let profileId = space.profileId
                else {
                    return nil
                }
                return browserManager.profileManager.profiles.first { $0.id == profileId }
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            firstProfile: { [weak browserManager] in
                browserManager?.profileManager.profiles.first
            }
        )
    }

    private static func makeTabReloadPolicyRuntime(
        for browserManager: BrowserManager
    ) -> TabReloadPolicyRuntime {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            protectionCoordinator: { [weak browserManager] in
                browserManager?.protectionCoordinator
            },
            runtimePermissionController: { [weak browserManager] in
                browserManager?.permissionRuntime.runtimePermissionController
            }
        )
    }

    private static func makeTabHistorySwipeRuntime(
        for browserManager: BrowserManager
    ) -> TabHistorySwipeRuntime {
        .live(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.cancelWindowMutationsAfterHistorySwipe(in: windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.flushWindowMutationsAfterHistorySwipe(in: windowId)
            }
        )
    }

    private static func makeTabHistoryRecordingRuntime(
        for browserManager: BrowserManager
    ) -> TabHistoryRecordingRuntime {
        .live(
            historyManager: { [weak browserManager] in
                browserManager?.historyManager
            },
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            }
        )
    }

    private static func makeTabFindInPageRuntime(
        for browserManager: BrowserManager
    ) -> TabFindInPageRuntime {
        .live(
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.getWebView(for: tabId, in: windowId)
            }
        )
    }

    private static func makeTabExtensionPropertiesRuntime(
        for browserManager: BrowserManager
    ) -> TabExtensionPropertiesRuntime {
        .live(extensionsModule: { [weak browserManager] in
            browserManager?.extensionsModule
        })
    }

    private static func makeTabCloseLifecycleRuntime(
        for browserManager: BrowserManager
    ) -> TabCloseLifecycleRuntime {
        .live(
            cleanupZoomForTab: { [weak browserManager] tabId in
                browserManager?.zoomCommandOwner.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: { [weak browserManager] in
                browserManager?.compositorManager.updateTabVisibility()
            },
            removeTab: { [weak browserManager] tabId in
                browserManager?.tabManager.removeTab(tabId)
            }
        )
    }

    private static func makeTabLifecycleNavigationRuntime(
        for browserManager: BrowserManager
    ) -> TabLifecycleNavigationRuntime {
        .live(
            dependencies: TabLifecycleNavigationRuntime.LiveDependencies(
                tabSuspensionService: { [weak browserManager] in
                    browserManager?.tabSuspensionService
                },
                extensionsModule: { [weak browserManager] in
                    browserManager?.extensionsModule
                },
                loadZoomForTab: { [weak browserManager] tabId in
                    browserManager?.zoomCommandOwner.loadZoomForTab(tabId)
                },
                adBlockingModule: { [weak browserManager] in
                    browserManager?.adBlockingModule
                },
                enforceSiteDataPolicyAfterNavigation: { [weak browserManager] tab in
                    browserManager?.dataServices.siteDataPolicyEnforcementService
                        .enforceBlockStorageIfNeeded(
                            for: tab.url,
                            profile: tab.resolveProfile()
                        )
                },
                authenticationManager: { [weak browserManager] in
                    browserManager?.authenticationManager
                },
                webViewCoordinator: { [weak browserManager] in
                    browserManager?.webViewCoordinator
                }
            )
        )
    }

    private static func makeTabPermissionRuntime(
        for browserManager: BrowserManager
    ) -> TabPermissionRuntime {
        .live(
            permissionBridges: { [weak browserManager] in
                browserManager?.permissionRuntime.permissionBridges
            },
            handlePermissionLifecycleEvent: { [weak browserManager] event in
                browserManager?.permissionRuntime.permissionLifecycleController.handle(event)
            },
            isActiveGlancePreviewSurface: { [weak browserManager] tabId, webView in
                guard let browserManager,
                      let session = browserManager.glanceManager.currentSession,
                      session.previewTab.id == tabId,
                      session.previewTab.existingWebView === webView,
                      let windowState = browserManager.windowRegistry?.windows[session.windowId],
                      browserManager.glanceManager.activeSession(for: windowState)?.id == session.id
                else {
                    return false
                }
                return true
            }
        )
    }

    private static func makeTabWebViewCleanupRuntime(
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

    private static func makeTabNormalWebViewExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabNormalWebViewExtensionRuntime {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            }
        )
    }

    private static func makeTabNavigationDelegateRuntime(
        for browserManager: BrowserManager
    ) -> TabNavigationDelegateRuntime {
        .live(
            externalSchemePermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.externalSchemePermissionBridge
            },
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            }
        )
    }

    private static func makeTabFaviconExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabFaviconExtensionRuntime {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            extensionSurfaceStore: { [weak browserManager] in
                browserManager?.extensionsModule.surfaceStore
            }
        )
    }

    private static func makeTabPopupHandlingRuntime(
        for browserManager: BrowserManager
    ) -> TabPopupHandlingRuntime {
        .live(
            dependencies: TabPopupHandlingRuntime.LiveDependencies(
                isAvailable: { [weak browserManager] in
                    browserManager != nil
                },
                extensionsModule: { [weak browserManager] in
                    browserManager?.extensionsModule
                },
                popupPermissionBridge: { [weak browserManager] in
                    browserManager?.permissionRuntime.popupPermissionBridge
                },
                targetSpaceForOpener: { [weak browserManager] openerTab in
                    guard let browserManager else { return nil }
                    return TabPopupHandlingRuntime.targetSpace(
                        for: openerTab,
                        tabManager: browserManager.tabManager,
                        windowState: browserManager.windowState(containing: openerTab)
                    )
                },
                createNewTab: { [weak browserManager] url, space, activate in
                    browserManager?.tabManager.createNewTab(
                        url: url,
                        in: space,
                        activate: activate
                    )
                },
                materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                    browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
                },
                presentWebPopup: { [weak browserManager] configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                    browserManager?.auxiliaryWindowManager.presentWebPopup(
                        configuration: configuration,
                        request: request,
                        windowFeatures: windowFeatures,
                        openerTab: openerTab,
                        isExtensionOriginated: isExtensionOriginated,
                        shouldActivateApp: true
                    )
                },
                openerProfile: { [weak browserManager] openerTab in
                    guard let browserManager else { return nil }
                    return TabPopupHandlingRuntime.explicitPopupOpenerProfile(
                        for: openerTab,
                        windowRegistry: browserManager.windowRegistry,
                        profiles: browserManager.profileManager.profiles,
                        spaces: browserManager.tabManager.spaces
                    )
                },
                createPopupTab: { [weak browserManager] openerTab, activate in
                    browserManager?.createPopupTab(
                        from: openerTab,
                        activate: activate
                    )
                },
                windowStateContainingTab: { [weak browserManager] tab in
                    browserManager?.windowState(containing: tab)
                },
                selectTab: { [weak browserManager] tab, windowState in
                    browserManager?.selectTab(tab, in: windowState)
                }
            )
        )
    }

    private static func makeTabInstallNavigationRuntime(
        for browserManager: BrowserManager
    ) -> TabInstallNavigationRuntime {
        .live(userscriptsModule: { [weak browserManager] in
            browserManager?.userscriptsModule
        })
    }

    private static func makeTabWebKitUIRuntime(
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

    private static func makeTabWebViewReplacementRuntime(
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
                browserManager?.refreshCompositor(for: windowState)
            }
        )
    }

    private static func makeTabWebViewConfigurationContext(
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

    private static func makeTabDependencyDataServices(
        for browserManager: BrowserManager
    ) -> TabDependencyDataServices? {
        TabDependencyDataServices(
            faviconService: browserManager.dataServices.faviconService,
            faviconImageService: browserManager.dataServices.faviconImageService,
            visitedLinkStore: browserManager.dataServices.visitedLinkStore
        )
    }

    private static func makeTabBrowserActionService(
        for browserManager: BrowserManager
    ) -> TabBrowserActionService {
        TabBrowserActionService(
            hasBrowserRuntime: { [weak browserManager] in
                browserManager != nil
            },
            webPageMenuAppearance: { [weak browserManager] tab, fallback in
                guard let browserManager else { return fallback }
                return webPageMenuAppearance(
                    for: tab,
                    fallback: fallback,
                    browserManager: browserManager
                )
            },
            canBookmark: { [weak browserManager] tab in
                browserManager?.bookmarkManager.canBookmark(tab) ?? false
            },
            requestBookmarkEditorFromMenu: { [weak browserManager] in
                browserManager?.bookmarkCommandOwner.requestBookmarkEditorForActiveWindowFromMenu()
            },
            canStartContextMenuDownload: { [weak browserManager] in
                browserManager != nil
            },
            startContextMenuDownload: { [weak browserManager] webView, request in
                guard let browserManager else { return }
                startContextMenuDownload(
                    webView: webView,
                    request: request,
                    browserManager: browserManager
                )
            },
            openURLInForegroundTab: { [weak browserManager] url, tab in
                guard let browserManager else { return }
                openURLInForegroundTab(url, from: tab, browserManager: browserManager)
            },
            openURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyNavigationOwner.openURLsInNewWindow(urls)
            },
            notificationPermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.notificationPermissionBridge
            },
            shortcutLaunchURL: { [weak browserManager] shortcutPinId in
                browserManager?.tabManager.shortcutPin(by: shortcutPinId)?.launchURL
            },
            reconcileExtensionRuntimeOnUserGesture: { [weak browserManager] tab, reason in
                browserManager?.extensionsModule.reconcileExtensionRuntimeOnUserGestureIfNeeded(
                    tab,
                    reason: reason
                )
            },
            isCurrentTab: { [weak browserManager] tab in
                guard let browserManager else { return false }
                return isCurrentTab(tab, browserManager: browserManager)
            },
            activate: { [weak browserManager] tab in
                browserManager?.tabManager.setActiveTab(tab)
            }
        )
    }

    private static func webPageMenuAppearance(
        for tab: Tab,
        fallback: NSAppearance?,
        browserManager: BrowserManager
    ) -> NSAppearance? {
        guard let windowState = browserManager.windowState(containing: tab),
              let settings = browserManager.sumiSettings
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

    private static func startContextMenuDownload(
        webView: WKWebView,
        request: URLRequest,
        browserManager: BrowserManager
    ) {
        guard let url = request.url else { return }

        let callback: @MainActor @Sendable (WKDownload) -> Void = { [weak browserManager] download in
            _ = browserManager?.downloadManager.addDownload(
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

    private static func openURLInForegroundTab(
        _ url: URL,
        from tab: Tab,
        browserManager: BrowserManager
    ) {
        guard let windowState = browserManager.windowState(containing: tab) else { return }

        _ = browserManager.openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: tab.spaceId
            )
        )
    }

    private static func isCurrentTab(_ tab: Tab, browserManager: BrowserManager) -> Bool {
        guard let windowState = browserManager.windowState(containing: tab) else { return false }
        return browserManager.currentTab(for: windowState)?.id == tab.id
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
                return protectionCoordinator()?.currentTabDiagnostics(
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
