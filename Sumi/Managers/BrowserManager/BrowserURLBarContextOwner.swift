import SwiftUI
import WebKit

@MainActor
final class BrowserURLBarContextOwner {
    struct Dependencies {
        let zoomContext: @MainActor () -> URLBarZoomContext
        let permissionContext: @MainActor () -> URLBarPermissionContext
        let extensionActionContext: @MainActor () -> URLBarExtensionActionContext
        let urlBarHubContext: @MainActor () -> URLBarHubBrowserContext
        let hubPopoverPresenter: @MainActor () -> URLBarHubPopoverPresenter
        let bookmarkEditorPresentationRequest: @MainActor () -> SumiBookmarkEditorPresentationRequest?
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let tabForID: @MainActor (UUID) -> Tab?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let profiles: @MainActor () -> [Profile]
        let currentProfile: @MainActor () -> Profile?
        let siteControlsSnapshot: @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
        let focusFloatingBar: @MainActor (BrowserWindowState, String, Bool) -> Void
        let reloadPage: @MainActor (Tab, BrowserWindowState, String) -> Void
        let closeURLBarHubPopover: @MainActor (BrowserWindowState) -> Void
        let presentURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let toggleURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let isURLBarHubPopoverPresented: @MainActor (BrowserWindowState) -> Bool
        let presentToast: @MainActor (BrowserToast, BrowserWindowState) -> Void
        let toggleSidebar: @MainActor (BrowserWindowState) -> Void
        let navigationToolbarContext: @MainActor (BrowserWindowState) -> NavigationToolbarBrowserContext
        let navigationHistoryContext: @MainActor (BrowserWindowState) -> SumiNavigationHistoryContext
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
            webView: dependencies.webView,
            profiles: dependencies.profiles,
            currentProfile: dependencies.currentProfile,
            siteControlsSnapshot: dependencies.siteControlsSnapshot,
            focusFloatingBar: dependencies.focusFloatingBar,
            reloadPage: dependencies.reloadPage,
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
        dependencies.urlBarHubContext()
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        dependencies.navigationToolbarContext(windowState)
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        dependencies.navigationHistoryContext(windowState)
    }
}

extension BrowserURLBarContextOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let dataServices = browserManager.dataServices
        let extensionsModule = browserManager.extensionsModule
        let userscriptsModule = browserManager.userscriptsModule
        let protectionCoordinator = browserManager.protectionCoordinator
        let urlBarHubPopoverPresenter = browserManager.chromePopoverRoutingOwner.urlBarHubPopoverPresenter
        let webViewRoutingService = browserManager.webViewRoutingService
        let zoomManager = browserManager.zoomManager
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: browserManager)
        )
        let navigationToolbarContextOwner = BrowserNavigationToolbarContextOwner(
            dependencies: BrowserNavigationToolbarContextOwner.Dependencies(
                currentTab: { [weak browserManager] windowState in
                    browserManager?.currentTab(for: windowState)
                },
                webView: { tab, windowState in
                    webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
                },
                faviconService: {
                    dataServices.faviconService
                },
                faviconImageService: {
                    dataServices.faviconImageService
                },
                openURLInCurrentTab: { [weak browserManager] url, windowState in
                    browserManager?.historyNavigationOwner.openHistoryURL(
                        url,
                        in: windowState,
                        preferredOpenMode: .currentTab
                    )
                },
                openNewTab: { [weak browserManager] urlString, context in
                    browserManager?.openNewTab(url: urlString, context: context)
                },
                openHistoryURLsInNewWindow: { [weak browserManager] urls in
                    browserManager?.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
                },
                goBack: { [weak browserManager] windowState in
                    browserManager?.historyNavigationOwner.goBack(in: windowState)
                },
                goForward: { [weak browserManager] windowState in
                    browserManager?.historyNavigationOwner.goForward(in: windowState)
                },
                reload: { [weak browserManager] tab, windowState in
                    browserManager?.windowScopedNavigationOwner.refreshWindowScopedPage(
                        tab: tab,
                        in: windowState,
                        reason: "NavigationToolbar.reload"
                    )
                }
            )
        )
        let extensionActionContext: @MainActor () -> URLBarExtensionActionContext = { [weak browserManager] in
            BrowserURLBarContextOwner.makeExtensionActionContext(
                browserManager: browserManager,
                extensionsModule: extensionsModule,
                userscriptsModule: userscriptsModule
            )
        }
        let siteControlsSnapshot: @MainActor (
            URL?,
            Profile?,
            Bool,
            Bool
        ) -> SiteControlsSnapshot = { url, profile, protectionReloadRequired, contentBlockerReloadRequired in
            BrowserURLBarContextOwner.siteControlsSnapshot(
                url: url,
                profile: profile,
                protectionCoordinator: protectionCoordinator,
                extensionsModule: extensionsModule,
                protectionReloadRequired: protectionReloadRequired,
                contentBlockerReloadRequired: contentBlockerReloadRequired
            )
        }
        let urlBarHubContextOwner = BrowserURLBarHubContextOwner(
            dependencies: .live(
                browserManager: browserManager,
                permissionContextOwner: permissionContextOwner,
                extensionActionContext: extensionActionContext,
                siteControlsSnapshot: siteControlsSnapshot
            )
        )
        return Self(
            zoomContext: { [weak browserManager] in
                BrowserURLBarContextOwner.makeZoomContext(
                    browserManager: browserManager,
                    zoomManager: zoomManager
                )
            },
            permissionContext: {
                permissionContextOwner.context
            },
            extensionActionContext: extensionActionContext,
            urlBarHubContext: {
                urlBarHubContextOwner.context
            },
            hubPopoverPresenter: {
                urlBarHubPopoverPresenter
            },
            bookmarkEditorPresentationRequest: { [weak browserManager] in
                browserManager?.bookmarkEditorPresentationRequest
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            tabForID: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            webView: { [weak browserManager] tab, windowState in
                browserManager?.windowOwnedWebView(for: tab, in: windowState.id)
            },
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            siteControlsSnapshot: siteControlsSnapshot,
            focusFloatingBar: { [weak browserManager] windowState, prefill, navigateCurrentTab in
                browserManager?.floatingBarRoutingOwner.focusFloatingBar(
                    in: windowState,
                    prefill: prefill,
                    navigateCurrentTab: navigateCurrentTab,
                    presentationReason: .keyboard
                )
            },
            reloadPage: { [weak browserManager] tab, windowState, reason in
                browserManager?.windowScopedNavigationOwner.refreshWindowScopedPage(
                    tab: tab,
                    in: windowState,
                    reason: reason
                )
            },
            closeURLBarHubPopover: { [weak browserManager] windowState in
                browserManager?.chromePopoverRoutingOwner.urlBarHubPopoverPresenter.close(in: windowState)
            },
            presentURLBarHubPopover: { [weak browserManager] windowState, context in
                browserManager?.chromePopoverRoutingOwner.urlBarHubPopoverPresenter.present(
                    in: windowState,
                    browserContext: context
                )
            },
            toggleURLBarHubPopover: { [weak browserManager] windowState, context in
                browserManager?.chromePopoverRoutingOwner.urlBarHubPopoverPresenter.toggle(
                    in: windowState,
                    browserContext: context
                )
            },
            isURLBarHubPopoverPresented: { [weak browserManager] windowState in
                browserManager?.chromePopoverRoutingOwner.urlBarHubPopoverPresenter.isPresented(in: windowState) ?? false
            },
            presentToast: { [weak browserManager] toast, windowState in
                browserManager?.toastPresenter.presentToast(toast, in: windowState)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.toggleSidebar(for: windowState)
            },
            navigationToolbarContext: { windowState in
                navigationToolbarContextOwner.navigationToolbarContext(for: windowState)
            },
            navigationHistoryContext: { windowState in
                navigationToolbarContextOwner.navigationHistoryContext(for: windowState)
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
            ensureActionMetadataLoadedIfNeeded: {
                extensionsModule.ensureActionMetadataLoadedIfNeeded()
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
                browserManager?.zoomCommandOwner.resetZoomCurrentTab(in: windowState)
            },
            zoomOutCurrentTab: { [weak browserManager] windowState in
                browserManager?.zoomCommandOwner.zoomOutCurrentTab(in: windowState)
            },
            zoomInCurrentTab: { [weak browserManager] windowState in
                browserManager?.zoomCommandOwner.zoomInCurrentTab(in: windowState)
            },
            requestPopover: { [weak browserManager] tab, windowState, source in
                browserManager?.zoomCommandOwner.requestZoomPopover(for: tab, in: windowState, source: source)
            }
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
