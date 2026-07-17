import Combine
import Foundation

@MainActor
final class BrowserURLBarHubCommandOwner {
    let boosts: SumiBoostsModule
    let extensions: SumiExtensionsModule

    private let settings: BrowserSettingsNavigationService
    private let sharing: BrowserSharingPickerPresentationOwner
    private let bookmarks: BrowserBookmarkEditorPresentationState

    init(
        boosts: SumiBoostsModule,
        extensions: SumiExtensionsModule,
        settings: BrowserSettingsNavigationService,
        sharing: BrowserSharingPickerPresentationOwner,
        bookmarks: BrowserBookmarkEditorPresentationState
    ) {
        self.boosts = boosts
        self.extensions = extensions
        self.settings = settings
        self.sharing = sharing
        self.bookmarks = bookmarks
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
