import Combine
import SwiftUI

@MainActor
extension BrowserManager {
    func sidebarHeaderBrowserContext(
        for windowState: BrowserWindowState
    ) -> SidebarHeaderBrowserContext {
        SidebarHeaderBrowserContext(
            navigationToolbarContext: navigationToolbarContext(for: windowState),
            urlBarBrowserContext: urlBarBrowserContext,
            toggleSidebar: { [weak self, weak windowState] in
                guard let windowState else { return }
                self?.toggleSidebar(for: windowState)
            }
        )
    }

    var urlBarBrowserContext: URLBarBrowserContext {
        URLBarBrowserContext(
            zoom: urlBarZoomContext,
            permission: urlBarPermissionContext,
            hub: urlBarHubBrowserContext,
            hubPopoverPresenter: urlBarHubPopoverPresenter,
            bookmarkEditorPresentationRequest: bookmarkEditorPresentationRequest,
            currentTab: { [weak self] windowState in
                self?.currentTab(for: windowState)
            },
            tabForID: { [weak self] tabId in
                self?.tabManager.tab(for: tabId)
            },
            profiles: { [weak self] in
                self?.profileManager.profiles ?? []
            },
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            siteControlsSnapshot: { [weak self] url, profile, protectionReloadRequired, contentBlockerReloadRequired in
                guard let self else {
                    return SiteControlsSnapshot.resolve(
                        url: url,
                        profile: profile,
                        protectionReloadRequired: protectionReloadRequired,
                        safariContentBlockerReloadRequired: contentBlockerReloadRequired
                    )
                }
                return self.urlBarSiteControlsSnapshot(
                    url: url,
                    profile: profile,
                    protectionReloadRequired: protectionReloadRequired,
                    contentBlockerReloadRequired: contentBlockerReloadRequired
                )
            },
            focusFloatingBar: { [weak self] windowState, prefill, navigateCurrentTab in
                self?.focusFloatingBar(
                    in: windowState,
                    prefill: prefill,
                    navigateCurrentTab: navigateCurrentTab
                )
            },
            closeURLBarHubPopover: { [weak self] windowState in
                self?.urlBarHubPopoverPresenter.close(in: windowState)
            },
            presentURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.urlBarHubPopoverPresenter.present(
                    in: windowState,
                    browserContext: self.urlBarHubBrowserContext
                )
            },
            toggleURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.urlBarHubPopoverPresenter.toggle(
                    in: windowState,
                    browserContext: self.urlBarHubBrowserContext
                )
            },
            isURLBarHubPopoverPresented: { [weak self] windowState in
                self?.urlBarHubPopoverPresenter.isPresented(in: windowState) ?? false
            },
            presentToast: { [weak self] toast, windowState in
                self?.presentToast(toast, in: windowState)
            },
            extensionActions: urlBarExtensionActionContext
        )
    }

    var urlBarHubBrowserContext: URLBarHubBrowserContext {
        URLBarHubBrowserContext(
            bookmarkManager: bookmarkManager,
            bookmarkPresentationRequest: bookmarkEditorPresentationRequest,
            extensionSurfaceStore: extensionSurfaceStore,
            extensionActions: urlBarExtensionActionContext,
            permission: urlBarPermissionContext,
            permissionDependencies: urlBarPermissionLoadDependencies,
            protectionCoordinator: protectionCoordinator,
            cleanupService: dataServices.websiteDataCleanupService,
            siteDataPolicyStore: dataServices.siteDataPolicyStore,
            siteDataPolicyEnforcementService: dataServices.siteDataPolicyEnforcementService,
            faviconService: dataServices.faviconService,
            protectionSettingsChanges: protectionCoordinator.settings.changesPublisher,
            protectionSitePolicyChanges: protectionCoordinator.sitePolicyChangesPublisher(),
            blockedPopupChanges: blockedPopupStore.objectWillChange.eraseVoid(),
            externalSchemeChanges: externalSchemeSessionStore.objectWillChange.eraseVoid(),
            indicatorEventChanges: permissionIndicatorEventStore.objectWillChange.eraseVoid(),
            permissionSiteActivityChanges: permissionSiteActivityStore.objectWillChange.eraseVoid(),
            boostChanges: boostsModule.store.changesPublisher,
            profiles: { [weak self] in
                self?.profileManager.profiles ?? []
            },
            currentProfile: { [weak self] in
                self?.currentProfile
            },
            webView: { [weak self] tab, windowState in
                self?.getWebView(for: tab.id, in: windowState.id)
            },
            siteControlsSnapshot: { [weak self] url, profile, protectionReloadRequired, contentBlockerReloadRequired in
                guard let self else {
                    return SiteControlsSnapshot.resolve(
                        url: url,
                        profile: profile,
                        protectionReloadRequired: protectionReloadRequired,
                        safariContentBlockerReloadRequired: contentBlockerReloadRequired
                    )
                }
                return self.urlBarSiteControlsSnapshot(
                    url: url,
                    profile: profile,
                    protectionReloadRequired: protectionReloadRequired,
                    contentBlockerReloadRequired: contentBlockerReloadRequired
                )
            },
            openExtensionSettings: { [weak self] windowState in
                self?.openSettingsTab(selecting: .extensions, in: windowState)
            },
            openSiteSettings: { [weak self] tab, windowState in
                self?.openSiteSettingsTab(focusing: tab, in: windowState)
            },
            setSafariContentBlockerSiteOverride: { [weak self] override, url in
                self?.extensionsModule.setSafariContentBlockerSiteOverride(
                    override,
                    for: url
                )
            },
            canBoost: { [weak self] url in
                self?.boostsModule.canBoost(url: url) ?? false
            },
            changedBoosts: { [weak self] url, profileId in
                self?.boostsModule.changedBoosts(for: url, profileId: profileId) ?? []
            },
            activeBoostId: { [weak self] url, profileId in
                self?.boostsModule.activeBoostId(for: url, profileId: profileId)
            },
            createBoostAndOpenEditor: { [weak self] tab, profile, windowState in
                guard let self else { return }
                try self.boostsModule.createBoostAndOpenEditor(
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            toggleActiveBoost: { [weak self] boost, isEphemeral in
                self?.boostsModule.toggleActiveBoost(boost, isEphemeral: isEphemeral)
            },
            presentBoostEditor: { [weak self] boost, tab, profile, windowState in
                self?.boostsModule.presentEditor(
                    boost: boost,
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            presentSharingServicePicker: { [weak self] items, source in
                self?.presentSharingServicePicker(items, source: source)
            },
            clearBookmarkEditorPresentationRequest: { [weak self] request in
                self?.clearBookmarkEditorPresentationRequest(request)
            }
        )
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak self, weak windowState] in
                guard let self, let windowState else { return nil }
                return self.currentTab(for: windowState)
            },
            webView: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return nil }
                return self.getWebView(for: tab.id, in: windowState.id)
            },
            historyContext: navigationHistoryContext(for: windowState)
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: dataServices.faviconService,
            faviconImageService: dataServices.faviconImageService,
            openURLInNewTab: { [weak self, weak windowState] url, selected, sourceTab in
                guard let self else { return }
                let targetWindowState = windowState ?? self.windowRegistry?.activeWindow
                let context: BrowserManager.TabOpenContext
                if selected, let targetWindowState {
                    context = .foreground(
                        windowState: targetWindowState,
                        sourceTab: sourceTab,
                        preferredSpaceId: targetWindowState.currentSpaceId
                    )
                } else {
                    context = .background(
                        windowState: targetWindowState,
                        sourceTab: sourceTab,
                        preferredSpaceId: targetWindowState?.currentSpaceId
                    )
                }

                self.openNewTab(url: url.absoluteString, context: context)
            },
            openURLsInNewWindow: { [weak self] urls in
                self?.openHistoryURLsInNewWindow(urls)
            }
        )
    }

    private var urlBarExtensionActionContext: URLBarExtensionActionContext {
        URLBarExtensionActionContext(
            orderedPinnedToolbarSlotCount: { [weak self] enabledExtensions in
                guard let self else { return 0 }
                return self.extensionsModule.orderedPinnedToolbarSlots(
                    enabledExtensions: enabledExtensions,
                    sumiScriptsManagerEnabled: self.userscriptsModule.isEnabled
                )
                .count
            },
            compactStrip: { [weak self] extensions, windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    ExtensionActionView(
                        extensions: extensions,
                        layout: .compactStrip,
                        browserContext: ExtensionActionBrowserContext.live(
                            browserManager: self,
                            windowState: windowState
                        )
                    )
                )
            },
            hubTiles: { [weak self] extensions, windowState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    ExtensionActionView(
                        extensions: extensions,
                        layout: .hubTiles,
                        browserContext: ExtensionActionBrowserContext.live(
                            browserManager: self,
                            windowState: windowState
                        )
                    )
                )
            },
            ensureActionSurfaceMetadataLoadedIfNeeded: { [weak self] in
                self?.extensionsModule.ensureActionSurfaceMetadataLoadedIfNeeded()
            },
            isPinnedToToolbar: { [weak self] extensionId in
                self?.extensionsModule.isPinnedToToolbar(extensionId) ?? false
            },
            sumiScriptsManagerEnabled: { [weak self] in
                self?.userscriptsModule.isEnabled ?? false
            }
        )
    }

    private var urlBarZoomContext: URLBarZoomContext {
        URLBarZoomContext(
            manager: zoomManager,
            stateRevision: zoomStateRevision,
            popoverRequest: zoomPopoverRequest,
            resetCurrentTab: { [weak self] windowState in
                self?.resetZoomCurrentTab(in: windowState)
            },
            zoomOutCurrentTab: { [weak self] windowState in
                self?.zoomOutCurrentTab(in: windowState)
            },
            zoomInCurrentTab: { [weak self] windowState in
                self?.zoomInCurrentTab(in: windowState)
            },
            requestPopover: { [weak self] tab, windowState, source in
                self?.requestZoomPopover(for: tab, in: windowState, source: source)
            }
        )
    }

    private var urlBarPermissionContext: URLBarPermissionContext {
        URLBarPermissionContext(
            coordinator: permissionCoordinator,
            runtimeController: runtimePermissionController,
            popupStore: blockedPopupStore,
            externalSchemeStore: externalSchemeSessionStore,
            indicatorEventStore: permissionIndicatorEventStore,
            systemPermissionService: systemPermissionService,
            externalAppResolver: externalAppResolver,
            siteActivityRevision: { [weak self] in
                self?.permissionSiteActivityStore.revision ?? 0
            },
            updateIndicator: { [weak self] viewModel, tab, windowState in
                guard let self else { return }
                viewModel.update(
                    tab: tab,
                    windowId: windowState.id,
                    browserManager: self
                )
            },
            updatePrompt: { [weak self] presenter, tab, windowState in
                guard let self else { return }
                presenter.update(
                    tab: tab,
                    windowState: windowState,
                    browserManager: self
                )
            }
        )
    }

    private var urlBarPermissionLoadDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: permissionCoordinator,
            systemPermissionService: systemPermissionService,
            runtimeController: runtimePermissionController,
            autoplayStore: SumiAutoplayPolicyStoreAdapter.shared,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore,
            indicatorEventStore: permissionIndicatorEventStore,
            siteActivityStore: permissionSiteActivityStore
        )
    }

    private func urlBarSiteControlsSnapshot(
        url: URL?,
        profile: Profile?,
        protectionReloadRequired: Bool,
        contentBlockerReloadRequired: Bool
    ) -> SiteControlsSnapshot {
        SiteControlsSnapshot.resolve(
            url: url,
            profile: profile,
            protectionCoordinator: protectionCoordinator,
            protectionBrowserRestartRequired: protectionCoordinator.settings.browserRestartRequired,
            protectionReloadRequired: protectionReloadRequired,
            extensionsModule: extensionsModule,
            safariContentBlockerReloadRequired: contentBlockerReloadRequired
        )
    }
}

private extension Publisher where Failure == Never {
    func eraseVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
