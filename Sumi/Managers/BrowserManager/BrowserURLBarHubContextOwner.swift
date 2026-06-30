import Combine
import Foundation
import WebKit

@MainActor
final class BrowserURLBarHubContextOwner {
    struct Dependencies {
        let bookmarkManager: @MainActor () -> SumiBookmarkManager
        let bookmarkEditorPresentationRequest: @MainActor () -> SumiBookmarkEditorPresentationRequest?
        let extensionSurfaceStore: @MainActor () -> BrowserExtensionSurfaceStore
        let extensionActionContext: @MainActor () -> URLBarExtensionActionContext
        let permissionContext: @MainActor () -> URLBarPermissionContext
        let permissionLoadDependencies: @MainActor () -> SumiCurrentSitePermissionsViewModel.LoadDependencies
        let protectionCoordinator: @MainActor () -> SumiProtectionCoordinator
        let cleanupService: @MainActor () -> any SumiWebsiteDataCleanupServicing
        let siteDataPolicyStore: @MainActor () -> any BrowserSiteDataPolicyStoring
        let siteDataPolicyEnforcementService: @MainActor () -> any BrowserSiteDataPolicyEnforcing
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let protectionSettingsChanges: @MainActor () -> AnyPublisher<Void, Never>
        let protectionSitePolicyChanges: @MainActor () -> AnyPublisher<Void, Never>
        let blockedPopupChanges: @MainActor () -> AnyPublisher<Void, Never>
        let externalSchemeChanges: @MainActor () -> AnyPublisher<Void, Never>
        let indicatorEventChanges: @MainActor () -> AnyPublisher<Void, Never>
        let permissionSiteActivityChanges: @MainActor () -> AnyPublisher<Void, Never>
        let boostChanges: @MainActor () -> AnyPublisher<Void, Never>
        let profiles: @MainActor () -> [Profile]
        let currentProfile: @MainActor () -> Profile?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let siteControlsSnapshot: @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
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
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var context: URLBarHubBrowserContext {
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
}

extension BrowserURLBarHubContextOwner.Dependencies {
    @MainActor
    static func live(
        browserManager: BrowserManager,
        permissionContextOwner: BrowserURLBarPermissionContextOwner,
        extensionActionContext: @escaping @MainActor () -> URLBarExtensionActionContext,
        siteControlsSnapshot: @escaping @MainActor (URL?, Profile?, Bool, Bool) -> SiteControlsSnapshot
    ) -> Self {
        let dataServices = browserManager.dataServices
        let boostsModule = browserManager.boostsModule
        let extensionsModule = browserManager.extensionsModule
        let extensionSurfaceStore = browserManager.extensionSurfaceStore
        let protectionCoordinator = browserManager.protectionCoordinator
        return Self(
            bookmarkManager: { [weak browserManager, bookmarkManager = browserManager.bookmarkManager] in
                browserManager?.bookmarkManager ?? bookmarkManager
            },
            bookmarkEditorPresentationRequest: { [weak browserManager] in
                browserManager?.bookmarkEditorPresentationRequest
            },
            extensionSurfaceStore: {
                extensionSurfaceStore
            },
            extensionActionContext: extensionActionContext,
            permissionContext: {
                permissionContextOwner.context
            },
            permissionLoadDependencies: {
                permissionContextOwner.loadDependencies
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
            protectionSettingsChanges: {
                protectionCoordinator.settings.changesPublisher
            },
            protectionSitePolicyChanges: {
                protectionCoordinator.sitePolicyChangesPublisher()
            },
            blockedPopupChanges: {
                permissionContextOwner.blockedPopupChanges
            },
            externalSchemeChanges: {
                permissionContextOwner.externalSchemeChanges
            },
            indicatorEventChanges: {
                permissionContextOwner.indicatorEventChanges
            },
            permissionSiteActivityChanges: {
                permissionContextOwner.siteActivityChanges
            },
            boostChanges: {
                boostsModule.store.changesPublisher
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
            siteControlsSnapshot: siteControlsSnapshot,
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
            }
        )
    }
}
