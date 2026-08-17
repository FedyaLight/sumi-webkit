import Combine
import Foundation

@MainActor
final class BrowserURLBarHubCommandOwner {
    let boosts: SumiBoostsModule
    let extensions: SumiExtensionsModule

    private let settings: BrowserSettingsNavigationService
    private let sharing: BrowserSharingPickerPresentationOwner
    private let bookmarks: BrowserBookmarkEditorPresentationState
    private let activePages: ActivePageResolver
    private let pageCommands: ActivePageCommandService
    private let webViews: BrowserWebViewRoutingService

    init(
        boosts: SumiBoostsModule,
        extensions: SumiExtensionsModule,
        settings: BrowserSettingsNavigationService,
        sharing: BrowserSharingPickerPresentationOwner,
        bookmarks: BrowserBookmarkEditorPresentationState,
        activePages: ActivePageResolver,
        pageCommands: ActivePageCommandService,
        webViews: BrowserWebViewRoutingService
    ) {
        self.boosts = boosts
        self.extensions = extensions
        self.settings = settings
        self.sharing = sharing
        self.bookmarks = bookmarks
        self.activePages = activePages
        self.pageCommands = pageCommands
        self.webViews = webViews
    }

    var bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest? {
        bookmarks.request
    }

    func openExtensionSettings(in windowState: BrowserWindowState) {
        settings.openSettings(selecting: .extensions, in: windowState)
    }

    func openSiteSettings(tab: Tab?, in windowState: BrowserWindowState) {
        settings.openSiteSettings(focusing: tab, in: windowState)
    }

    func reloadAfterProtectionPolicyChange(
        for tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let page = activePages.resolve(in: windowState),
              page.tab.id == tab.id
        else {
            return false
        }
        if tab.configurationPolicyRequiresNormalWebViewRebuild(
            for: page.url
        ) {
            webViews.loadPage(
                page.url,
                for: tab,
                in: windowState,
                reason: "URLBarHub.protectionPolicyChanged"
            )
            return true
        }
        return pageCommands.reload(
            page,
            reason: "URLBarHub.protectionPolicyChanged"
        ).ownsFutureOrSubmittedNavigation
    }

    func presentSharingPicker(
        items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        sharing.presentSharingServicePicker(items, source: source)
    }

    func clearBookmarkPresentation(
        _ request: SumiBookmarkEditorPresentationRequest
    ) {
        bookmarks.clear(request)
    }
}
