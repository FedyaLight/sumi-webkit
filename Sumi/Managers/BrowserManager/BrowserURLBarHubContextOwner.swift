import Foundation
import SumiDomain

@MainActor
final class BrowserURLBarHubContextOwner {
    let pageActionOwner: URLBarHubPageActionOwner
    private let bookmarks: SumiBookmarkManager
    private let permissions: BrowserURLBarPermissionContextOwner
    private let siteData: BrowserURLBarSiteDataContextOwner
    private let commands: BrowserURLBarHubCommandOwner
    private let pages: BrowserURLBarPageProjectionOwner

    init(
        bookmarks: SumiBookmarkManager,
        permissions: BrowserURLBarPermissionContextOwner,
        siteData: BrowserURLBarSiteDataContextOwner,
        commands: BrowserURLBarHubCommandOwner,
        pages: BrowserURLBarPageProjectionOwner,
        windows: WindowRegistry
    ) {
        let pageActionOwner = URLBarHubPageActionOwner()
        pageActionOwner.windowRegistry = windows
        self.pageActionOwner = pageActionOwner
        self.bookmarks = bookmarks
        self.permissions = permissions
        self.siteData = siteData
        self.commands = commands
        self.pages = pages
    }

    var permissionContext: URLBarPermissionContext {
        permissions.context
    }

    var bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest? {
        commands.bookmarkPresentationRequest
    }

    var extensionActionContext: URLBarExtensionActionContext {
        pages.extensionActionContext
    }

    var profiles: [Profile] {
        pages.profiles
    }

    var currentProfile: Profile? {
        pages.selectedProfile
    }

    func webView(for tab: Tab, in windowState: BrowserWindowState) -> WKWebView? {
        pages.webView(for: tab, in: windowState)
    }

    func siteControlsSnapshot(
        url: URL?,
        profile: Profile?,
        protectionReloadRequired: Bool,
        contentBlockerReloadRequired: Bool
    ) -> SiteControlsSnapshot {
        pages.siteControlsSnapshot(
            url: url,
            profile: profile,
            protectionReloadRequired: protectionReloadRequired,
            contentBlockerReloadRequired: contentBlockerReloadRequired
        )
    }

    var context: URLBarHubBrowserContext {
        let protection = siteData.protection
        let data = siteData.dataServices
        let boosts = commands.boosts
        let extensions = commands.extensions
        return URLBarHubBrowserContext(
            pageActionOwner: pageActionOwner,
            bookmarkManager: bookmarks,
            bookmarkPresentationRequest: commands.bookmarkPresentationRequest,
            extensionActions: pages.extensionActionContext,
            permission: permissions.context,
            permissionDependencies: permissions.loadDependencies,
            protectionCoordinator: protection,
            adblockZapperStore: siteData.adblockZapperStore,
            cleanupService: data.websiteDataCleanupService,
            profileWebsiteDataMutationService: data.profileWebsiteDataMutationService,
            siteDataPolicyStore: data.siteDataPolicyStore,
            siteDataPolicyEnforcementService: data.siteDataPolicyEnforcementService,
            faviconService: data.faviconService,
            faviconImageReader: data.faviconCapabilities.images,
            protectionSettingsChanges: protection.settings.changesPublisher,
            protectionSitePolicyChanges: protection.sitePolicyChangesPublisher(),
            blockedPopupChanges: permissions.blockedPopupChanges,
            externalSchemeChanges: permissions.externalSchemeChanges,
            indicatorEventChanges: permissions.indicatorEventChanges,
            permissionSiteActivityChanges: permissions.siteActivityChanges,
            boostChanges: boosts.changesPublisher,
            profiles: { [pages] in pages.profiles },
            currentProfile: { [pages] in pages.selectedProfile },
            webView: { [pages] tab, windowState in
                pages.webView(for: tab, in: windowState)
            },
            siteControlsSnapshot: { [pages] url, profile, protectionReload, blockerReload in
                pages.siteControlsSnapshot(
                    url: url,
                    profile: profile,
                    protectionReloadRequired: protectionReload,
                    contentBlockerReloadRequired: blockerReload
                )
            },
            openExtensionSettings: { [commands] windowState in
                commands.openExtensionSettings(in: windowState)
            },
            openSiteSettings: { [commands] tab, windowState in
                commands.openSiteSettings(tab: tab, in: windowState)
            },
            setSafariContentBlockerSiteOverride: { [extensions] override, url in
                extensions.setSafariContentBlockerSiteOverride(override, for: url)
            },
            canBoost: { [boosts] url in boosts.canBoost(url: url) },
            changedBoosts: { [boosts] url, profileID in
                boosts.changedBoosts(for: url, profileId: profileID)
            },
            activeBoostId: { [boosts] url, profileID in
                boosts.activeBoostId(for: url, profileId: profileID)
            },
            createBoostAndOpenEditor: { [boosts] tab, profile, windowState in
                try boosts.createBoostAndOpenEditor(
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            toggleActiveBoost: { [boosts] boost, isEphemeral in
                boosts.toggleActiveBoost(boost, isEphemeral: isEphemeral)
            },
            presentBoostEditor: { [boosts] boost, tab, profile, windowState in
                boosts.presentEditor(
                    boost: boost,
                    tab: tab,
                    profile: profile,
                    windowState: windowState
                )
            },
            presentSharingServicePicker: { [commands] items, source in
                commands.presentSharingPicker(items: items, source: source)
            },
            clearBookmarkEditorPresentationRequest: { [commands] request in
                commands.clearBookmarkPresentation(request)
            }
        )
    }
}
