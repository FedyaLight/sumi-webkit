import SwiftUI
import WebKit
import SumiDomain

@MainActor
final class BrowserURLBarContextOwner {
    struct HubPresentationCapabilities {
        let hubPopoverPresenter: URLBarHubPopoverPresenter
        let closeURLBarHubPopover: @MainActor (BrowserWindowState) -> Void
        let presentURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let toggleURLBarHubPopover: @MainActor (BrowserWindowState, URLBarHubBrowserContext) -> Void
        let isURLBarHubPopoverPresented: @MainActor (BrowserWindowState) -> Bool
    }

    struct PageChromeCapabilities {
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let tabForID: @MainActor (UUID) -> Tab?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let profiles: @MainActor () -> [Profile]
        let currentProfile: @MainActor () -> Profile?
        let siteControlsSnapshot: @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
        let focusFloatingBar: @MainActor (BrowserWindowState, String, Bool) -> Void
        let reloadPage: @MainActor (Tab, BrowserWindowState, String) -> Void
        let copyURLToClipboard: @MainActor (String, BrowserWindowState) -> Void
        let toggleSidebar: @MainActor (BrowserWindowState) -> Void
        let bookmarkEditorPresentationRequest: @MainActor () -> SumiBookmarkEditorPresentationRequest?
    }

    private let zoomManager: ZoomManager
    private weak var browserManager: BrowserManager?
    private let permissionContextOwner: BrowserURLBarPermissionContextOwner
    private let hubContextOwner: BrowserURLBarHubContextOwner
    private let navigationToolbarContextOwner: BrowserNavigationToolbarContextOwner
    private let extensionActionContext: @MainActor () -> URLBarExtensionActionContext
    private let hubPresentation: HubPresentationCapabilities
    private let pageChrome: PageChromeCapabilities

    init(
        browserManager: BrowserManager,
        zoomManager: ZoomManager,
        permissionContextOwner: BrowserURLBarPermissionContextOwner,
        hubContextOwner: BrowserURLBarHubContextOwner,
        navigationToolbarContextOwner: BrowserNavigationToolbarContextOwner,
        extensionActionContext: @escaping @MainActor () -> URLBarExtensionActionContext,
        hubPresentation: HubPresentationCapabilities,
        pageChrome: PageChromeCapabilities
    ) {
        self.browserManager = browserManager
        self.zoomManager = zoomManager
        self.permissionContextOwner = permissionContextOwner
        self.hubContextOwner = hubContextOwner
        self.navigationToolbarContextOwner = navigationToolbarContextOwner
        self.extensionActionContext = extensionActionContext
        self.hubPresentation = hubPresentation
        self.pageChrome = pageChrome
    }

    convenience init(browserManager: BrowserManager) {
        let dataServices = browserManager.dataServices
        let extensionsModule = browserManager.extensionsModule
        let userscriptsModule = browserManager.userscriptsModule
        let protectionCoordinator = browserManager.protectionCoordinator
        let urlBarHubPopoverPresenter = browserManager.chromeBundle.commands.urlBarHubPopoverPresenter
        let webViewRoutingService = browserManager.webViewRoutingService
        let zoomManager = browserManager.zoomManager
        let permissionContextOwner = BrowserURLBarPermissionContextOwner(
            browserManager: browserManager
        )
        let navigationToolbarContextOwner = BrowserNavigationToolbarContextOwner(
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
            },
            webView: { tab, windowState in
                webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
            },
            faviconService: {
                dataServices.faviconService
            },
            faviconImageReader: {
                dataServices.faviconCapabilities.images
            },
            openURLInCurrentTab: { [weak browserManager] url, windowState in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: .currentTab
                )
            },
            openNewTab: { [weak browserManager] urlString, context in
                browserManager?.tabLifecycleService.opening.openNewTab(url: urlString, context: context)
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
            },
            goBack: { [weak browserManager] windowState in
                browserManager?.historyBundle.historyNavigationOwner.goBack(in: windowState)
            },
            goForward: { [weak browserManager] windowState in
                browserManager?.historyBundle.historyNavigationOwner.goForward(in: windowState)
            },
            reload: { [weak browserManager] tab, windowState in
                browserManager?.windowSessionBundle.scopedNavigationOwner.refreshWindowScopedPage(
                    tab: tab,
                    in: windowState,
                    reason: "NavigationToolbar.reload"
                )
            }
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
        let hubContextOwner = BrowserURLBarHubContextOwner(
            browserManager: browserManager,
            permissionContextOwner: permissionContextOwner,
            extensionActionContext: extensionActionContext,
            siteControlsSnapshot: siteControlsSnapshot
        )
        self.init(
            browserManager: browserManager,
            zoomManager: zoomManager,
            permissionContextOwner: permissionContextOwner,
            hubContextOwner: hubContextOwner,
            navigationToolbarContextOwner: navigationToolbarContextOwner,
            extensionActionContext: extensionActionContext,
            hubPresentation: HubPresentationCapabilities(
                hubPopoverPresenter: urlBarHubPopoverPresenter,
                closeURLBarHubPopover: { [weak browserManager] windowState in
                    browserManager?.chromeBundle.commands.urlBarHubPopoverPresenter.close(in: windowState)
                },
                presentURLBarHubPopover: { [weak browserManager] windowState, context in
                    browserManager?.chromeBundle.commands.urlBarHubPopoverPresenter.present(
                        in: windowState,
                        browserContext: context
                    )
                },
                toggleURLBarHubPopover: { [weak browserManager] windowState, context in
                    browserManager?.chromeBundle.commands.urlBarHubPopoverPresenter.toggle(
                        in: windowState,
                        browserContext: context
                    )
                },
                isURLBarHubPopoverPresented: { [weak browserManager] windowState in
                    browserManager?.chromeBundle.commands.urlBarHubPopoverPresenter.isPresented(in: windowState) ?? false
                }
            ),
            pageChrome: PageChromeCapabilities(
                currentTab: { [weak browserManager] windowState in
                    browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
                },
                tabForID: { [weak browserManager] tabId in
                    browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
                },
                webView: { [weak browserManager] tab, windowState in
                    browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
                },
                profiles: { [weak browserManager] in
                    browserManager?.profileManager.profiles ?? []
                },
                currentProfile: { [weak browserManager] in
                    browserManager?.currentProfile
                },
                siteControlsSnapshot: siteControlsSnapshot,
                focusFloatingBar: { [weak browserManager] windowState, prefill, navigateCurrentTab in
                    browserManager?.urlBarBundle.floatingBarRoutingOwner.focusFloatingBar(
                        in: windowState,
                        prefill: prefill,
                        navigateCurrentTab: navigateCurrentTab,
                        presentationReason: .keyboard
                    )
                },
                reloadPage: { [weak browserManager] tab, windowState, reason in
                    browserManager?.windowSessionBundle.scopedNavigationOwner.refreshWindowScopedPage(
                        tab: tab,
                        in: windowState,
                        reason: reason
                    )
                },
                copyURLToClipboard: { [weak browserManager] urlString, windowState in
                    _ = browserManager?.urlBarBundle.commands.copyURLToPasteboard(urlString, in: windowState)
                },
                toggleSidebar: { [weak browserManager] windowState in
                    browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar(for: windowState)
                },
                bookmarkEditorPresentationRequest: { [weak browserManager] in
                    browserManager?.bookmarkEditorPresentationRequest
                }
            )
        )
    }

    func sidebarHeaderContext(for windowState: BrowserWindowState) -> SidebarHeaderBrowserContext {
        SidebarHeaderBrowserContext(
            navigationToolbarContext: navigationToolbarContext(for: windowState),
            urlBarBrowserContext: urlBarContext,
            toggleSidebar: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.pageChrome.toggleSidebar(windowState)
            }
        )
    }

    var urlBarContext: URLBarBrowserContext {
        URLBarBrowserContext(
            zoom: makeZoomContext(),
            permission: permissionContextOwner.context,
            hub: urlBarHubContext,
            hubPopoverPresenter: hubPresentation.hubPopoverPresenter,
            bookmarkEditorPresentationRequest: pageChrome.bookmarkEditorPresentationRequest(),
            currentTab: pageChrome.currentTab,
            tabForID: pageChrome.tabForID,
            webView: pageChrome.webView,
            profiles: pageChrome.profiles,
            currentProfile: pageChrome.currentProfile,
            siteControlsSnapshot: pageChrome.siteControlsSnapshot,
            focusFloatingBar: pageChrome.focusFloatingBar,
            reloadPage: pageChrome.reloadPage,
            closeURLBarHubPopover: hubPresentation.closeURLBarHubPopover,
            presentURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.hubPresentation.presentURLBarHubPopover(windowState, self.urlBarHubContext)
            },
            toggleURLBarHubPopover: { [weak self] windowState in
                guard let self else { return }
                self.hubPresentation.toggleURLBarHubPopover(windowState, self.urlBarHubContext)
            },
            isURLBarHubPopoverPresented: hubPresentation.isURLBarHubPopoverPresented,
            copyURLToClipboard: pageChrome.copyURLToClipboard,
            extensionActions: extensionActionContext()
        )
    }

    var urlBarHubContext: URLBarHubBrowserContext {
        hubContextOwner.context
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        navigationToolbarContextOwner.navigationToolbarContext(for: windowState)
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        navigationToolbarContextOwner.navigationHistoryContext(for: windowState)
    }

    private func makeZoomContext() -> URLBarZoomContext {
        URLBarZoomContext(
            manager: zoomManager,
            stateRevision: browserManager?.zoomStateRevision ?? 0,
            resetCurrentTab: { [weak browserManager] windowState in
                browserManager?.chromeBundle.zoomCommandOwner.resetZoomCurrentTab(in: windowState)
            },
            zoomOutCurrentTab: { [weak browserManager] windowState in
                browserManager?.chromeBundle.zoomCommandOwner.zoomOutCurrentTab(in: windowState)
            },
            zoomInCurrentTab: { [weak browserManager] windowState in
                browserManager?.chromeBundle.zoomCommandOwner.zoomInCurrentTab(in: windowState)
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
