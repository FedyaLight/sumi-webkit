import Combine
import Foundation
import WebKit

@MainActor
final class BrowserURLBarHubContextOwner {
    /// Closures that cannot be replaced by a stable object reference.
    struct Capabilities {
        let extensionActionContext: @MainActor () -> URLBarExtensionActionContext
        let siteControlsSnapshot: @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
        let profiles: @MainActor () -> [Profile]
        let currentProfile: @MainActor () -> Profile?
        let bookmarkEditorPresentationRequest: @MainActor () -> SumiBookmarkEditorPresentationRequest?
        let openExtensionSettings: @MainActor (BrowserWindowState) -> Void
        let openSiteSettings: @MainActor (Tab?, BrowserWindowState) -> Void
        let presentSharingServicePicker: @MainActor ([Any], SidebarTransientPresentationSource) -> Void
        let clearBookmarkEditorPresentationRequest: @MainActor (SumiBookmarkEditorPresentationRequest) -> Void
    }

    private let bookmarkManager: SumiBookmarkManager
    private let permissionContextOwner: BrowserURLBarPermissionContextOwner
    private let protectionCoordinator: SumiProtectionCoordinator
    private let adblockZapperStore: SumiAdblockZapperStore
    private let dataServices: BrowserManagerDataServices
    private let boostsModule: SumiBoostsModule
    private let extensionsModule: SumiExtensionsModule
    private let webViewRoutingService: BrowserWebViewRoutingService
    private let capabilities: Capabilities

    init(
        bookmarkManager: SumiBookmarkManager,
        permissionContextOwner: BrowserURLBarPermissionContextOwner,
        protectionCoordinator: SumiProtectionCoordinator,
        adblockZapperStore: SumiAdblockZapperStore,
        dataServices: BrowserManagerDataServices,
        boostsModule: SumiBoostsModule,
        extensionsModule: SumiExtensionsModule,
        webViewRoutingService: BrowserWebViewRoutingService,
        capabilities: Capabilities
    ) {
        self.bookmarkManager = bookmarkManager
        self.permissionContextOwner = permissionContextOwner
        self.protectionCoordinator = protectionCoordinator
        self.adblockZapperStore = adblockZapperStore
        self.dataServices = dataServices
        self.boostsModule = boostsModule
        self.extensionsModule = extensionsModule
        self.webViewRoutingService = webViewRoutingService
        self.capabilities = capabilities
    }

    convenience init(
        browserManager: BrowserManager,
        permissionContextOwner: BrowserURLBarPermissionContextOwner,
        extensionActionContext: @escaping @MainActor () -> URLBarExtensionActionContext,
        siteControlsSnapshot: @escaping @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot,
        settingsNavigation: BrowserSettingsNavigationService
    ) {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        self.init(
            bookmarkManager: browserManager.bookmarkManager,
            permissionContextOwner: permissionContextOwner,
            protectionCoordinator: browserManager.protectionCoordinator,
            adblockZapperStore: browserManager.adblockZapperStore,
            dataServices: browserManager.dataServices,
            boostsModule: browserManager.optionalModules.boosts,
            extensionsModule: browserManager.optionalModules.extensions,
            webViewRoutingService: browserManager.webViewRoutingService,
            capabilities: Capabilities(
                extensionActionContext: extensionActionContext,
                siteControlsSnapshot: siteControlsSnapshot,
                profiles: { [weak browserManager] in
                    browserManager?.profileManager.profiles ?? []
                },
                currentProfile: { [currentProfileAuthority] in
                    currentProfileAuthority.currentProfile
                },
                bookmarkEditorPresentationRequest: { [weak browserManager] in
                    browserManager?.bookmarkEditorPresentationRequest
                },
                openExtensionSettings: { [settingsNavigation] windowState in
                    settingsNavigation.openSettings(selecting: .extensions, in: windowState)
                },
                openSiteSettings: { [settingsNavigation] tab, windowState in
                    settingsNavigation.openSiteSettings(focusing: tab, in: windowState)
                },
                presentSharingServicePicker: { [weak browserManager] items, source in
                    browserManager?.chromeBundle.nativeDialogPresentationOwner.presentSharingServicePicker(
                        items,
                        source: source
                    )
                },
                clearBookmarkEditorPresentationRequest: { [weak browserManager] request in
                    browserManager?.bookmarkBundle.bookmarkCommandOwner.clearBookmarkEditorPresentationRequest(request)
                }
            )
        )
    }

    var context: URLBarHubBrowserContext {
        URLBarHubBrowserContext(
            bookmarkManager: bookmarkManager,
            bookmarkPresentationRequest: capabilities.bookmarkEditorPresentationRequest(),
            extensionActions: capabilities.extensionActionContext(),
            permission: permissionContextOwner.context,
            permissionDependencies: permissionContextOwner.loadDependencies,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            cleanupService: dataServices.websiteDataCleanupService,
            profileWebsiteDataMutationService: dataServices.profileWebsiteDataMutationService,
            siteDataPolicyStore: dataServices.siteDataPolicyStore,
            siteDataPolicyEnforcementService: dataServices.siteDataPolicyEnforcementService,
            faviconService: dataServices.faviconService,
            faviconImageReader: dataServices.faviconCapabilities.images,
            protectionSettingsChanges: protectionCoordinator.settings.changesPublisher,
            protectionSitePolicyChanges: protectionCoordinator.sitePolicyChangesPublisher(),
            blockedPopupChanges: permissionContextOwner.blockedPopupChanges,
            externalSchemeChanges: permissionContextOwner.externalSchemeChanges,
            indicatorEventChanges: permissionContextOwner.indicatorEventChanges,
            permissionSiteActivityChanges: permissionContextOwner.siteActivityChanges,
            boostChanges: boostsModule.changesPublisher,
            profiles: capabilities.profiles,
            currentProfile: capabilities.currentProfile,
            webView: { [webViewRoutingService] tab, windowState in
                webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
            },
            siteControlsSnapshot: capabilities.siteControlsSnapshot,
            openExtensionSettings: capabilities.openExtensionSettings,
            openSiteSettings: capabilities.openSiteSettings,
            setSafariContentBlockerSiteOverride: { [extensionsModule] override, url in
                extensionsModule.setSafariContentBlockerSiteOverride(override, for: url)
            },
            canBoost: { [boostsModule] url in
                boostsModule.canBoost(url: url)
            },
            changedBoosts: { [boostsModule] url, profileId in
                boostsModule.changedBoosts(for: url, profileId: profileId)
            },
            activeBoostId: { [boostsModule] url, profileId in
                boostsModule.activeBoostId(for: url, profileId: profileId)
            },
            createBoostAndOpenEditor: { [boostsModule] tab, profile, windowState in
                try boostsModule.createBoostAndOpenEditor(
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            toggleActiveBoost: { [boostsModule] boost, isEphemeral in
                boostsModule.toggleActiveBoost(boost, isEphemeral: isEphemeral)
            },
            presentBoostEditor: { [boostsModule] boost, tab, profile, windowState in
                boostsModule.presentEditor(
                    boost: boost,
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            presentSharingServicePicker: capabilities.presentSharingServicePicker,
            clearBookmarkEditorPresentationRequest: capabilities.clearBookmarkEditorPresentationRequest
        )
    }
}
