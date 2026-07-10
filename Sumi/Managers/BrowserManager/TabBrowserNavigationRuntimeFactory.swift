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
                browserManager?.extensionsModule
            }
        )
    }

    static func profileResolutionRuntime(
        for browserManager: BrowserManager
    ) -> TabProfileResolutionRuntime {
        .make(
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

    static func reloadPolicyRuntime(
        for browserManager: BrowserManager
    ) -> TabReloadPolicyRuntime {
        .make(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            protectionCoordinator: { [weak browserManager] in
                browserManager?.protectionCoordinator
            },
            browserConfiguration: { [weak browserManager] in
                browserManager?.browserConfiguration
            },
            runtimePermissionController: { [weak browserManager] in
                browserManager?.permissionRuntime.runtimePermissionController
            }
        )
    }

    static func historySwipeRuntime(
        for browserManager: BrowserManager
    ) -> TabHistorySwipeRuntime {
        .make(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.windowSessionBundle.visualMutationOwner.cancelWindowMutationsAfterHistorySwipe(in: windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                browserManager?.windowSessionBundle.visualMutationOwner.flushWindowMutationsAfterHistorySwipe(in: windowId)
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
        return .make(
            dependencies: TabLifecycleNavigationRuntime.LiveDependencies(
                resetTabSuspensionRevisitProtection: {
                    [weak tabSuspensionController] tab in
                    tabSuspensionController?.navigationDidStart(for: tab)
                },
                extensionsModule: { [weak browserManager] in
                    browserManager?.extensionsModule
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
                webViewCoordinator: { [weak browserManager] in
                    browserManager?.webViewCoordinator
                }
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
            browserManager?.userscriptsModule
        })
    }
}

@MainActor
extension TabHistorySwipeRuntime {
    static func make(
        webViewCoordinator: @escaping () -> WebViewCoordinator?,
        cancelWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void,
        flushWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            windowIDContaining: { webView in
                webViewCoordinator()?.ownershipQuery
                    .trackedOwner(containing: webView)?.windowID
            },
            beginHistorySwipeProtection: { tabId, webView, originURL, originHistoryItem in
                webViewCoordinator()?.protectionRuntime.beginHistorySwipe(
                    tabID: tabId,
                    webView: webView,
                    originURL: originURL,
                    originHistoryItem: originHistoryItem
                )
            },
            finishHistorySwipeProtection: { tabId, webView, currentURL, currentHistoryItem in
                webViewCoordinator()?.protectionRuntime.finishHistorySwipe(
                    tabID: tabId,
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
extension TabLifecycleNavigationRuntime {
    struct LiveDependencies {
        let resetTabSuspensionRevisitProtection: (Tab) -> Void
        let extensionsModule: () -> SumiExtensionsModule?
        let loadZoomForTab: (UUID, WKWebView) -> Void
        let adBlockingModule: () -> SumiAdBlockingModule?
        let adblockZapperStore: () -> SumiAdblockZapperStore?
        let enforceSiteDataPolicyAfterNavigation: (Tab) -> Void
        let authenticationManager: () -> AuthenticationManager?
        let webViewCoordinator: () -> WebViewCoordinator?
    }

    static func make(dependencies: LiveDependencies) -> Self {
        Self(
            resetRevisitProtection: { tab in
                dependencies.resetTabSuspensionRevisitProtection(tab)
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
                dependencies.webViewCoordinator()?.websiteDataCleanupService
                    .navigationWillStart(
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
                dependencies.webViewCoordinator()?.websiteDataCleanupService
                    .isSuppressingNavigation(
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
                dependencies.webViewCoordinator()?.websiteDataCleanupService
                    .navigationDidTerminate(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: navigationLifetime,
                        succeeded: succeeded
                    )
            },
            handleDestructiveDataCleanupProcessTermination: { webView in
                dependencies.webViewCoordinator()?.websiteDataCleanupService
                    .webContentProcessDidTerminate(on: webView)
                    == true
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
extension TabReloadPolicyRuntime {
    static func make(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        protectionCoordinator: @escaping () -> SumiProtectionCoordinator?,
        browserConfiguration: @escaping () -> BrowserConfiguration?,
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
            autoplayPolicy: { url, profile in
                guard let profile,
                      let browserConfiguration = browserConfiguration()
                else { return .default }
                return browserConfiguration.resolvedAutoplayPolicy(for: url, profile: profile)
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
