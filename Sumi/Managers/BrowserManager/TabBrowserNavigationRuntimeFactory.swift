import Foundation
import WebKit

@MainActor
enum TabBrowserNavigationRuntimeFactory {
    static func navigationCommandRuntime(
        for browserManager: BrowserManager
    ) -> TabNavigationCommandRuntime {
        .make(
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            extensionsModule: { [weak browserManager] in
                browserManager?.optionalModules.extensions
            }
        )
    }

    static func profileResolutionRuntime(
        for browserManager: BrowserManager
    ) -> TabProfileResolutionRuntime {
        .make(
            ephemeralProfileForTab: { [weak browserManager] tabId, profileId in
                guard let browserManager else { return nil }
                if let tracked = browserManager.windowRegistry?.windows.values.first(where: { window in
                    window.ephemeralTabs.contains(where: { $0.id == tabId })
                })?.ephemeralProfile,
                   tracked.id == profileId {
                    return tracked
                }
                return browserManager.profileManager
                    .ephemeralProfile(withID: profileId)
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            spaceProfile: { [weak browserManager] spaceId in
                guard let browserManager,
                      let space = browserManager.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId }),
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

    static func reloadPolicies(
        for browserManager: BrowserManager
    ) -> TabReloadPolicies {
        TabReloadPolicies(
            safariContentBlockers: BrowserSafariContentBlockerPolicy(
                extensions: browserManager.optionalModules.extensions
            ),
            protection: BrowserProtectionPolicy(
                protection: browserManager.protectionCoordinator
            ),
            autoplay: BrowserAutoplayPolicy(
                configuration: browserManager.browserConfiguration,
                permissionController: browserManager.permissionRuntime
                    .runtimePermissionController
            )
        )
    }

    static func historySwipeRuntime(
        for browserManager: BrowserManager
    ) -> TabHistorySwipeRuntime {
        let ownershipQuery = browserManager.webViewRuntime.ownershipQuery
        let protection = browserManager.webViewRuntime.protectionRuntime
        return .make(
            ownershipQuery: ownershipQuery,
            protection: protection,
            cancelWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.shellRuntime.windowVisuals.cancelWindowMutationsAfterHistorySwipe(in: windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.shellRuntime.windowVisuals.flushWindowMutationsAfterHistorySwipe(in: windowId)
            }
        )
    }

    static func historyRecordingRuntime(
        for browserManager: BrowserManager
    ) -> TabHistoryRecordingRuntime {
        .make(
            historyManager: { [weak browserManager] in
                browserManager?.historyManager
            },
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            }
        )
    }

    static func findInPageRuntime(
        for browserManager: BrowserManager
    ) -> TabFindInPageRuntime {
        .make(
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.webViewRoutingService.webView(for: tabId, in: windowId)
            }
        )
    }

    static func lifecycleNavigationRuntime(
        for browserManager: BrowserManager
    ) -> TabLifecycleNavigationRuntime {
        let tabSuspensionController = browserManager.tabSuspensionController
        let websiteDataCleanup = browserManager.webViewRuntime.websiteDataCleanupService
        return .make(
            dependencies: TabLifecycleNavigationRuntime.LiveDependencies(
                resetTabSuspensionRevisitProtection: {
                    [weak tabSuspensionController] tab in
                    tabSuspensionController?.navigationDidStart(for: tab)
                },
                reconcileDocumentSuspensionState: {
                    [weak tabSuspensionController] _ in
                    tabSuspensionController?.scheduleReconciliation(
                        reason: "document-suspension-state"
                    )
                },
                extensionsModule: { [weak browserManager] in
                    browserManager?.optionalModules.extensions
                },
                loadZoomForTab: { [weak browserManager] tabId, webView in
                    browserManager?.chromeBundle.zoomCommandOwner.loadZoomForTab(
                        tabId,
                        on: webView
                    )
                },
                adBlockingModule: { [weak browserManager] in
                    browserManager?.adBlockingModule
                },
                adblockZapperStore: { [weak browserManager] in
                    browserManager?.adblockZapperStore
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
                websiteDataCleanup: websiteDataCleanup
            )
        )
    }

    static func navigationDelegateRuntime(
        for browserManager: BrowserManager
    ) -> TabNavigationDelegateRuntime {
        .make(
            externalSchemePermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.externalSchemePermissionBridge
            },
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            },
            autoplayPolicy: { [weak browserManager] url, profile in
                browserManager?.permissionRuntime.autoplayStore.effectivePolicy(
                    for: url,
                    profile: profile
                ) ?? .default
            }
        )
    }

    static func installNavigationRuntime(
        for browserManager: BrowserManager
    ) -> TabInstallNavigationRuntime {
        .make(userscriptsModule: { [weak browserManager] in
            browserManager?.optionalModules.userscripts
        })
    }
}

@MainActor
extension TabHistorySwipeRuntime {
    static func make(
        ownershipQuery: WebViewOwnershipQuery,
        protection: WebViewProtectionRuntime,
        cancelWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void,
        flushWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            windowIDContaining: { webView in
                ownershipQuery
                    .trackedOwner(containing: webView)?.windowID
            },
            beginHistorySwipeProtection: { tabId, webView, originURL, originHistoryItem in
                protection.beginHistorySwipe(
                    tabID: tabId,
                    webView: webView,
                    originURL: originURL,
                    originHistoryItem: originHistoryItem
                )
            },
            finishHistorySwipeProtection: { tabId, webView, currentURL, currentHistoryItem in
                protection.finishHistorySwipe(
                    tabID: tabId,
                    webView: webView,
                    currentURL: currentURL,
                    currentHistoryItem: currentHistoryItem
                )
            },
            cancelWindowMutationsAfterHistorySwipe: cancelWindowMutationsAfterHistorySwipe,
            flushWindowMutationsAfterHistorySwipe: flushWindowMutationsAfterHistorySwipe
        )
    }
}

@MainActor
extension TabLifecycleNavigationRuntime {
    struct LiveDependencies {
        let resetTabSuspensionRevisitProtection: (Tab) -> Void
        let reconcileDocumentSuspensionState: (Tab) -> Void
        let extensionsModule: () -> SumiExtensionsModule?
        let loadZoomForTab: (UUID, WKWebView) -> Void
        let adBlockingModule: () -> SumiAdBlockingModule?
        let adblockZapperStore: () -> SumiAdblockZapperStore?
        let enforceSiteDataPolicyAfterNavigation: (Tab) -> Void
        let authenticationManager: () -> AuthenticationManager?
        let websiteDataCleanup: WebsiteDataCleanupService
    }

    static func make(dependencies: LiveDependencies) -> Self {
        Self(
            resetRevisitProtection: { tab in
                dependencies.resetTabSuspensionRevisitProtection(tab)
            },
            reconcileDocumentSuspensionState:
                dependencies.reconcileDocumentSuspensionState,
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
                   let profile = tab.resolveProfile(),
                   let store = dependencies.adblockZapperStore() {
                    SumiAdblockZapperInjector.applySavedRules(
                        to: webView,
                        host: host,
                        profilePartitionId: profile.id.uuidString,
                        isEphemeralProfile: profile.isEphemeral,
                        store: store
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
            destructiveDataCleanupNavigationWillStart: {
                webView,
                navigationID,
                navigationLifetime,
                targetURL,
                semanticRevision in
                dependencies.websiteDataCleanup.navigationWillStart(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: navigationLifetime,
                        targetURL: targetURL,
                        semanticRevision: semanticRevision
                    )
            },
            isPreparingForDataCleanupNavigation: {
                webView,
                navigationID,
                navigationLifetime in
                dependencies.websiteDataCleanup.isSuppressingNavigation(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: navigationLifetime
                    ) == true
            },
            finishDestructiveDataCleanupNavigation: {
                webView,
                navigationID,
                navigationLifetime,
                succeeded in
                dependencies.websiteDataCleanup.navigationDidTerminate(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: navigationLifetime,
                        succeeded: succeeded
                    )
            },
            handleDestructiveDataCleanupProcessTermination: { webView in
                dependencies.websiteDataCleanup
                    .webContentProcessDidTerminate(on: webView)
            }
        )
    }
}

@MainActor
extension TabNavigationDelegateRuntime {
    static func make(
        externalSchemePermissionBridge: @escaping () -> SumiExternalSchemePermissionBridge?,
        downloadManager: @escaping () -> DownloadManager?,
        autoplayPolicy: @escaping @MainActor (URL?, Profile?) -> SumiAutoplayPolicy
    ) -> Self {
        Self(
            externalSchemePermissionBridge: externalSchemePermissionBridge,
            downloadManager: downloadManager,
            autoplayPolicy: autoplayPolicy
        )
    }
}

@MainActor
extension TabInstallNavigationRuntime {
    static func make(userscriptsModule: @escaping () -> SumiUserscriptsModule?) -> Self {
        Self(
            interceptInstallNavigation: { url in
                userscriptsModule()?.interceptInstallNavigationIfNeeded(url) == true
            }
        )
    }
}

@MainActor
extension TabFindInPageRuntime {
    static func make(
        webView: @escaping (_ tabId: UUID, _ windowId: UUID) -> WKWebView?
    ) -> Self {
        Self(
            webView: webView
        )
    }
}

@MainActor
extension TabHistoryRecordingRuntime {
    static func make(
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
    static func make(settings: @escaping () -> SumiSettingsService?) -> Self {
        Self(
            resolvedSearchEngineTemplate: {
                settings()?.resolvedSearchEngineTemplate
            },
            prepareExtensionPageNavigation: { _, _, _ in
                .notNeeded
            }
        )
    }

    static func make(
        settings: @escaping () -> SumiSettingsService?,
        extensionsModule: @escaping () -> SumiExtensionsModule?
    ) -> Self {
        Self(
            resolvedSearchEngineTemplate: {
                settings()?.resolvedSearchEngineTemplate
            },
            prepareExtensionPageNavigation: { tab, url, reason in
                extensionsModule()?.prepareExtensionPageNavigationIfNeeded(
                    tab,
                    targetURL: url,
                    reason: reason
                ) ?? .notNeeded
            }
        )
    }
}

@MainActor
extension TabProfileResolutionRuntime {
    static func make(
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
