import Foundation

@MainActor
extension BrowserManager {
    func requestBookmarkEditorForActiveWindowFromMenu() {
        bookmarkCommandOwner.requestBookmarkEditorForActiveWindowFromMenu()
    }

    func clearBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest) {
        bookmarkCommandOwner.clearBookmarkEditorPresentationRequest(request)
    }

    func openBookmarksTab(
        selecting folderID: String? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        bookmarkCommandOwner.openBookmarksTab(selecting: folderID, in: windowState)
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        bookmarkCommandOwner.openBookmarkURLFromMenuItem(url)
    }

    func openBookmarkURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        bookmarkCommandOwner.openBookmarkURL(
            url,
            in: windowState,
            preferredOpenMode: preferredOpenMode
        )
    }

    func manageBookmarksFromMenu() {
        bookmarkCommandOwner.manageBookmarksFromMenu()
    }

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        bookmarkCommandOwner.canBookmarkAllTabsInActiveWindow()
    }

    func bookmarkAllTabsFromMenu() {
        bookmarkCommandOwner.bookmarkAllTabsFromMenu()
    }

    func bookmarkTabs(
        _ tabs: [Tab],
        folderTitle: String,
        parentID: String?
    ) throws -> SumiBookmarkAllTabsResult {
        try bookmarkCommandOwner.bookmarkTabs(
            tabs,
            folderTitle: folderTitle,
            parentID: parentID
        )
    }

    func importBookmarksFromMenu() {
        bookmarkCommandOwner.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        bookmarkCommandOwner.exportBookmarksFromMenu()
    }
}
