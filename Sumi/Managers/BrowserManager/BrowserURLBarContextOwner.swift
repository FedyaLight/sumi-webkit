import Combine
import SwiftUI
import WebKit

@MainActor
final class BrowserURLBarContextOwner {
    struct Dependencies {
        let zoomContext: @MainActor () -> URLBarZoomContext
        let permissionContext: @MainActor () -> URLBarPermissionContext
        let permissionLoadDependencies: @MainActor () -> SumiCurrentSitePermissionsViewModel.LoadDependencies
        let extensionActionContext: @MainActor () -> URLBarExtensionActionContext
        let hubPopoverPresenter: @MainActor () -> URLBarHubPopoverPresenter
        let bookmarkEditorPresentationRequest: @MainActor () -> SumiBookmarkEditorPresentationRequest?
        let bookmarkManager: @MainActor () -> SumiBookmarkManager
        let extensionSurfaceStore: @MainActor () -> BrowserExtensionSurfaceStore
        let protectionCoordinator: @MainActor () -> SumiProtectionCoordinator
        let cleanupService: @MainActor () -> any SumiWebsiteDataCleanupServicing
        let siteDataPolicyStore: @MainActor () -> any BrowserSiteDataPolicyStoring
        let siteDataPolicyEnforcementService: @MainActor () -> any BrowserSiteDataPolicyEnforcing
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let protectionSettingsChanges: @MainActor () -> AnyPublisher<Void, Never>
        let protectionSitePolicyChanges: @MainActor () -> AnyPublisher<Void, Never>
        let blockedPopupChanges: @MainActor () -> AnyPublisher<Void, Never>
        let externalSchemeChanges: @MainActor () -> AnyPublisher<Void, Never>
        let indicatorEventChanges: @MainActor () -> AnyPublisher<Void, Never>
        let permissionSiteActivityChanges: @MainActor () -> AnyPublisher<Void, Never>
        let boostChanges: @MainActor () -> AnyPublisher<Void, Never>
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let tabForID: @MainActor (UUID) -> Tab?
        let profiles: @MainActor () -> [Profile]
        let currentProfile: @MainActor () -> Profile?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let siteControlsSnapshot: @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
        let focusFloatingBar: @MainActor (BrowserWindowState, String, Bool) -> Void
        let closeURLBarHubPopover: @MainActor (BrowserWindowState) -> Void
        let presentURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let toggleURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let isURLBarHubPopoverPresented: @MainActor (BrowserWindowState) -> Bool
        let presentToast: @MainActor (BrowserToast, BrowserWindowState) -> Void
        let openExtensionSettings: @MainActor (BrowserWindowState) -> Void
        let openSiteSettings: @MainActor (Tab?, BrowserWindowState) -> Void
        let setSafariContentBlockerSiteOverride: @MainActor (SumiSafariContentBlockerSiteOverride, URL) -> Void
        let canBoost: @MainActor (URL?) -> Bool
        let changedBoosts: @MainActor (URL?, UUID?) -> [SumiBoost]
        let activeBoostId: @MainActor (URL?, UUID?) -> UUID?
        let createBoostAndOpenEditor: @MainActor (Tab, Profile?, BrowserWindowState) throws -> Void
        let toggleActiveBoost: @MainActor (SumiBoost, Bool) -> Void
        let presentBoostEditor: @MainActor (SumiBoost, Tab, Profile?, BrowserWindowState) -> Void
        let presentSharingServicePicker: @MainActor ([Any], SidebarTransientPresentationSource) -> Void
        let clearBookmarkEditorPresentationRequest: @MainActor (SumiBookmarkEditorPresentationRequest) -> Void
        let toggleSidebar: @MainActor (BrowserWindowState) -> Void
        let openURLFromNavigationHistory: @MainActor (URL, Bool, Tab?, BrowserWindowState?) -> Void
        let openHistoryURLsInNewWindow: @MainActor ([URL]) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func sidebarHeaderContext(for windowState: BrowserWindowState) -> SidebarHeaderBrowserContext {
        SidebarHeaderBrowserContext(
            navigationToolbarContext: navigationToolbarContext(for: windowState),
            urlBarBrowserContext: urlBarContext,
            toggleSidebar: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.dependencies.toggleSidebar(windowState)
            }
        )
    }

    var urlBarContext: URLBarBrowserContext {
        URLBarBrowserContext(
            zoom: dependencies.zoomContext(),
            permission: dependencies.permissionContext(),
            hub: urlBarHubContext,
            hubPopoverPresenter: dependencies.hubPopoverPresenter(),
            bookmarkEditorPresentationRequest: dependencies.bookmarkEditorPresentationRequest(),
            currentTab: dependencies.currentTab,
            tabForID: dependencies.tabForID,
            profiles: dependencies.profiles,
            currentProfile: dependencies.currentProfile,
            siteControlsSnapshot: dependencies.siteControlsSnapshot,
            focusFloatingBar: dependencies.focusFloatingBar,
            closeURLBarHubPopover: dependencies.closeURLBarHubPopover,
            presentURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.dependencies.presentURLBarHubPopover(windowState, self.urlBarHubContext)
            },
            toggleURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.dependencies.toggleURLBarHubPopover(windowState, self.urlBarHubContext)
            },
            isURLBarHubPopoverPresented: dependencies.isURLBarHubPopoverPresented,
            presentToast: dependencies.presentToast,
            extensionActions: dependencies.extensionActionContext()
        )
    }

    var urlBarHubContext: URLBarHubBrowserContext {
        URLBarHubBrowserContext(
            bookmarkManager: dependencies.bookmarkManager(),
            bookmarkPresentationRequest: dependencies.bookmarkEditorPresentationRequest(),
            extensionSurfaceStore: dependencies.extensionSurfaceStore(),
            extensionActions: dependencies.extensionActionContext(),
            permission: dependencies.permissionContext(),
            permissionDependencies: dependencies.permissionLoadDependencies(),
            protectionCoordinator: dependencies.protectionCoordinator(),
            cleanupService: dependencies.cleanupService(),
            siteDataPolicyStore: dependencies.siteDataPolicyStore(),
            siteDataPolicyEnforcementService: dependencies.siteDataPolicyEnforcementService(),
            faviconService: dependencies.faviconService(),
            protectionSettingsChanges: dependencies.protectionSettingsChanges(),
            protectionSitePolicyChanges: dependencies.protectionSitePolicyChanges(),
            blockedPopupChanges: dependencies.blockedPopupChanges(),
            externalSchemeChanges: dependencies.externalSchemeChanges(),
            indicatorEventChanges: dependencies.indicatorEventChanges(),
            permissionSiteActivityChanges: dependencies.permissionSiteActivityChanges(),
            boostChanges: dependencies.boostChanges(),
            profiles: dependencies.profiles,
            currentProfile: dependencies.currentProfile,
            webView: dependencies.webView,
            siteControlsSnapshot: dependencies.siteControlsSnapshot,
            openExtensionSettings: dependencies.openExtensionSettings,
            openSiteSettings: dependencies.openSiteSettings,
            setSafariContentBlockerSiteOverride: dependencies.setSafariContentBlockerSiteOverride,
            canBoost: dependencies.canBoost,
            changedBoosts: dependencies.changedBoosts,
            activeBoostId: dependencies.activeBoostId,
            createBoostAndOpenEditor: dependencies.createBoostAndOpenEditor,
            toggleActiveBoost: dependencies.toggleActiveBoost,
            presentBoostEditor: dependencies.presentBoostEditor,
            presentSharingServicePicker: dependencies.presentSharingServicePicker,
            clearBookmarkEditorPresentationRequest: dependencies.clearBookmarkEditorPresentationRequest
        )
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak self, weak windowState] in
                guard let self, let windowState else { return nil }
                return self.dependencies.currentTab(windowState)
            },
            webView: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return nil }
                return self.dependencies.webView(tab, windowState)
            },
            historyContext: navigationHistoryContext(for: windowState)
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            openURLInNewTab: { [weak self, weak windowState] url, selected, sourceTab in
                guard let self else { return }
                self.dependencies.openURLFromNavigationHistory(
                    url,
                    selected,
                    sourceTab,
                    windowState
                )
            },
            openURLsInNewWindow: dependencies.openHistoryURLsInNewWindow
        )
    }
}

extension BrowserURLBarContextOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let dataServices = browserManager.dataServices
        let boostsModule = browserManager.boostsModule
        let extensionsModule = browserManager.extensionsModule
        let userscriptsModule = browserManager.userscriptsModule
        let extensionSurfaceStore = browserManager.extensionSurfaceStore
        let permissionRuntime = browserManager.permissionRuntime
        let protectionCoordinator = browserManager.protectionCoordinator
        let urlBarHubPopoverPresenter = browserManager.urlBarHubPopoverPresenter
        let zoomManager = browserManager.zoomManager
        return Self(
            zoomContext: { [weak browserManager] in
                BrowserURLBarContextOwner.makeZoomContext(
                    browserManager: browserManager,
                    zoomManager: zoomManager
                )
            },
            permissionContext: { [weak browserManager] in
                BrowserURLBarContextOwner.makePermissionContext(
                    browserManager: browserManager,
                    permissionRuntime: permissionRuntime
                )
            },
            permissionLoadDependencies: {
                BrowserURLBarContextOwner.makePermissionLoadDependencies(
                    permissionRuntime: permissionRuntime
                )
            },
            extensionActionContext: { [weak browserManager] in
                BrowserURLBarContextOwner.makeExtensionActionContext(
                    browserManager: browserManager,
                    extensionsModule: extensionsModule,
                    userscriptsModule: userscriptsModule
                )
            },
            hubPopoverPresenter: {
                urlBarHubPopoverPresenter
            },
            bookmarkEditorPresentationRequest: { [weak browserManager] in
                browserManager?.bookmarkEditorPresentationRequest
            },
            bookmarkManager: { [weak browserManager, bookmarkManager = browserManager.bookmarkManager] in
                browserManager?.bookmarkManager ?? bookmarkManager
            },
            extensionSurfaceStore: {
                extensionSurfaceStore
            },
            protectionCoordinator: {
                protectionCoordinator
            },
            cleanupService: {
                dataServices.websiteDataCleanupService
            },
            siteDataPolicyStore: {
                dataServices.siteDataPolicyStore
            },
            siteDataPolicyEnforcementService: {
                dataServices.siteDataPolicyEnforcementService
            },
            faviconService: {
                dataServices.faviconService
            },
            faviconImageService: {
                dataServices.faviconImageService
            },
            protectionSettingsChanges: {
                protectionCoordinator.settings.changesPublisher
            },
            protectionSitePolicyChanges: {
                protectionCoordinator.sitePolicyChangesPublisher()
            },
            blockedPopupChanges: {
                permissionRuntime.blockedPopupStore.objectWillChange.eraseVoid()
            },
            externalSchemeChanges: {
                permissionRuntime.externalSchemeSessionStore.objectWillChange.eraseVoid()
            },
            indicatorEventChanges: {
                permissionRuntime.permissionIndicatorEventStore.objectWillChange.eraseVoid()
            },
            permissionSiteActivityChanges: {
                permissionRuntime.permissionSiteActivityStore.objectWillChange.eraseVoid()
            },
            boostChanges: {
                boostsModule.store.changesPublisher
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            tabForID: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            webView: { [weak browserManager] tab, windowState in
                browserManager?.getWebView(for: tab.id, in: windowState.id)
            },
            siteControlsSnapshot: { url, profile, protectionReloadRequired, contentBlockerReloadRequired in
                BrowserURLBarContextOwner.siteControlsSnapshot(
                    url: url,
                    profile: profile,
                    protectionCoordinator: protectionCoordinator,
                    extensionsModule: extensionsModule,
                    protectionReloadRequired: protectionReloadRequired,
                    contentBlockerReloadRequired: contentBlockerReloadRequired
                )
            },
            focusFloatingBar: { [weak browserManager] windowState, prefill, navigateCurrentTab in
                browserManager?.focusFloatingBar(
                    in: windowState,
                    prefill: prefill,
                    navigateCurrentTab: navigateCurrentTab
                )
            },
            closeURLBarHubPopover: { [weak browserManager] windowState in
                browserManager?.urlBarHubPopoverPresenter.close(in: windowState)
            },
            presentURLBarHubPopover: { [weak browserManager] windowState, context in
                browserManager?.urlBarHubPopoverPresenter.present(
                    in: windowState,
                    browserContext: context
                )
            },
            toggleURLBarHubPopover: { [weak browserManager] windowState, context in
                browserManager?.urlBarHubPopoverPresenter.toggle(
                    in: windowState,
                    browserContext: context
                )
            },
            isURLBarHubPopoverPresented: { [weak browserManager] windowState in
                browserManager?.urlBarHubPopoverPresenter.isPresented(in: windowState) ?? false
            },
            presentToast: { [weak browserManager] toast, windowState in
                browserManager?.presentToast(toast, in: windowState)
            },
            openExtensionSettings: { [weak browserManager] windowState in
                browserManager?.openSettingsTab(selecting: .extensions, in: windowState)
            },
            openSiteSettings: { [weak browserManager] tab, windowState in
                browserManager?.openSiteSettingsTab(focusing: tab, in: windowState)
            },
            setSafariContentBlockerSiteOverride: { override, url in
                extensionsModule.setSafariContentBlockerSiteOverride(
                    override,
                    for: url
                )
            },
            canBoost: { url in
                boostsModule.canBoost(url: url)
            },
            changedBoosts: { url, profileId in
                boostsModule.changedBoosts(for: url, profileId: profileId)
            },
            activeBoostId: { url, profileId in
                boostsModule.activeBoostId(for: url, profileId: profileId)
            },
            createBoostAndOpenEditor: { tab, profile, windowState in
                try boostsModule.createBoostAndOpenEditor(
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            toggleActiveBoost: { boost, isEphemeral in
                boostsModule.toggleActiveBoost(boost, isEphemeral: isEphemeral)
            },
            presentBoostEditor: { boost, tab, profile, windowState in
                boostsModule.presentEditor(
                    boost: boost,
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            presentSharingServicePicker: { [weak browserManager] items, source in
                browserManager?.presentSharingServicePicker(items, source: source)
            },
            clearBookmarkEditorPresentationRequest: { [weak browserManager] request in
                browserManager?.clearBookmarkEditorPresentationRequest(request)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.toggleSidebar(for: windowState)
            },
            openURLFromNavigationHistory: { [weak browserManager] url, selected, sourceTab, windowState in
                BrowserURLBarContextOwner.openURLFromNavigationHistory(
                    browserManager: browserManager,
                    url: url,
                    selected: selected,
                    sourceTab: sourceTab,
                    windowState: windowState
                )
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.openHistoryURLsInNewWindow(urls)
            }
        )
    }
}

private extension BrowserURLBarContextOwner {
    static func makeExtensionActionContext(
        browserManager: BrowserManager?,
        extensionsModule: SumiExtensionsModule,
        userscriptsModule: SumiUserscriptsModule
    ) -> URLBarExtensionActionContext {
        URLBarExtensionActionContext(
            orderedPinnedToolbarSlotCount: { enabledExtensions in
                extensionsModule.orderedPinnedToolbarSlots(
                    enabledExtensions: enabledExtensions,
                    sumiScriptsManagerEnabled: userscriptsModule.isEnabled
                )
                .count
            },
            compactStrip: { [weak browserManager] extensions, windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    ExtensionActionView(
                        extensions: extensions,
                        layout: .compactStrip,
                        browserContext: ExtensionActionBrowserContext.live(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                    )
                )
            },
            hubTiles: { [weak browserManager] extensions, windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    ExtensionActionView(
                        extensions: extensions,
                        layout: .hubTiles,
                        browserContext: ExtensionActionBrowserContext.live(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                    )
                )
            },
            ensureActionSurfaceMetadataLoadedIfNeeded: {
                extensionsModule.ensureActionSurfaceMetadataLoadedIfNeeded()
            },
            isPinnedToToolbar: { extensionId in
                extensionsModule.isPinnedToToolbar(extensionId)
            },
            sumiScriptsManagerEnabled: {
                userscriptsModule.isEnabled
            }
        )
    }

    static func makeZoomContext(
        browserManager: BrowserManager?,
        zoomManager: ZoomManager
    ) -> URLBarZoomContext {
        URLBarZoomContext(
            manager: zoomManager,
            stateRevision: browserManager?.zoomStateRevision ?? 0,
            popoverRequest: browserManager?.zoomPopoverRequest,
            resetCurrentTab: { [weak browserManager] windowState in
                browserManager?.resetZoomCurrentTab(in: windowState)
            },
            zoomOutCurrentTab: { [weak browserManager] windowState in
                browserManager?.zoomOutCurrentTab(in: windowState)
            },
            zoomInCurrentTab: { [weak browserManager] windowState in
                browserManager?.zoomInCurrentTab(in: windowState)
            },
            requestPopover: { [weak browserManager] tab, windowState, source in
                browserManager?.requestZoomPopover(for: tab, in: windowState, source: source)
            }
        )
    }

    static func makePermissionContext(
        browserManager: BrowserManager?,
        permissionRuntime: BrowserManagerPermissionRuntime
    ) -> URLBarPermissionContext {
        return URLBarPermissionContext(
            coordinator: permissionRuntime.permissionCoordinator,
            runtimeController: permissionRuntime.runtimePermissionController,
            popupStore: permissionRuntime.blockedPopupStore,
            externalSchemeStore: permissionRuntime.externalSchemeSessionStore,
            indicatorEventStore: permissionRuntime.permissionIndicatorEventStore,
            systemPermissionService: permissionRuntime.systemPermissionService,
            externalAppResolver: permissionRuntime.externalAppResolver,
            siteActivityRevision: { [weak browserManager] in
                browserManager?.permissionSiteActivityStore.revision ?? 0
            },
            updateIndicator: { [weak browserManager] viewModel, tab, windowState in
                guard let browserManager else { return }
                viewModel.update(
                    tab: tab,
                    windowId: windowState.id,
                    browserManager: browserManager
                )
            },
            updatePrompt: { [weak browserManager] presenter, tab, windowState in
                guard let browserManager else { return }
                presenter.update(
                    tab: tab,
                    windowState: windowState,
                    browserManager: browserManager
                )
            }
        )
    }

    static func makePermissionLoadDependencies(
        permissionRuntime: BrowserManagerPermissionRuntime
    ) -> SumiCurrentSitePermissionsViewModel.LoadDependencies {
        return SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: permissionRuntime.permissionCoordinator,
            systemPermissionService: permissionRuntime.systemPermissionService,
            runtimeController: permissionRuntime.runtimePermissionController,
            autoplayStore: SumiAutoplayPolicyStoreAdapter.shared,
            blockedPopupStore: permissionRuntime.blockedPopupStore,
            externalSchemeSessionStore: permissionRuntime.externalSchemeSessionStore,
            indicatorEventStore: permissionRuntime.permissionIndicatorEventStore,
            siteActivityStore: permissionRuntime.permissionSiteActivityStore
        )
    }

    static func siteControlsSnapshot(
        url: URL?,
        profile: Profile?,
        protectionCoordinator: SumiProtectionCoordinator,
        extensionsModule: SumiExtensionsModule,
        protectionReloadRequired: Bool,
        contentBlockerReloadRequired: Bool
    ) -> SiteControlsSnapshot {
        return SiteControlsSnapshot.resolve(
            url: url,
            profile: profile,
            protectionCoordinator: protectionCoordinator,
            protectionBrowserRestartRequired: protectionCoordinator.settings.browserRestartRequired,
            protectionReloadRequired: protectionReloadRequired,
            extensionsModule: extensionsModule,
            safariContentBlockerReloadRequired: contentBlockerReloadRequired
        )
    }

    static func openURLFromNavigationHistory(
        browserManager: BrowserManager?,
        url: URL,
        selected: Bool,
        sourceTab: Tab?,
        windowState: BrowserWindowState?
    ) {
        guard let browserManager else { return }
        let targetWindowState = windowState ?? browserManager.windowRegistry?.activeWindow
        let context: BrowserTabOpenContext
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

        browserManager.openNewTab(url: url.absoluteString, context: context)
    }
}

private extension Publisher where Failure == Never {
    func eraseVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
