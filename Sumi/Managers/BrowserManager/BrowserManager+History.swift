import Foundation

@MainActor
extension BrowserManager {
    enum HistoryOpenMode {
        case currentTab
        case newTab
        case newWindow
    }

    var canOfferStartupSessionRestoreShortcut: Bool {
        recentlyClosedRestoreOwner.canOfferStartupSessionRestoreShortcut
    }

    var canRestoreAnyLastSession: Bool {
        recentlyClosedRestoreOwner.canRestoreAnyLastSession
    }

    var canGoBackInActiveWindow: Bool {
        historyNavigationOwner.canGoBackInActiveWindow
    }

    var canGoForwardInActiveWindow: Bool {
        historyNavigationOwner.canGoForwardInActiveWindow
    }

    func canGoBack(in windowState: BrowserWindowState) -> Bool {
        historyNavigationOwner.canGoBack(in: windowState)
    }

    func canGoForward(in windowState: BrowserWindowState) -> Bool {
        historyNavigationOwner.canGoForward(in: windowState)
    }

    func goBackInActiveWindow() {
        historyNavigationOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        historyNavigationOwner.goForwardInActiveWindow()
    }

    func goBack(in windowState: BrowserWindowState) {
        historyNavigationOwner.goBack(in: windowState)
    }

    func goForward(in windowState: BrowserWindowState) {
        historyNavigationOwner.goForward(in: windowState)
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        historyNavigationOwner.openHistoryTab(selecting: range, in: windowState)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        historyNavigationOwner.openHistoryURLFromMenuItem(url)
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        historyNavigationOwner.openHistoryURL(url, in: windowState, preferredOpenMode: preferredOpenMode)
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        historyNavigationOwner.openURLsInNewTabs(urls, in: windowState)
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        historyNavigationOwner.openHistoryURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
        historyNavigationOwner.openURLsInNewWindow(urls)
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        historyNavigationOwner.openHistoryURLsInNewWindow(urls)
    }

    func reopenMostRecentClosedItem() {
        recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        recentlyClosedRestoreOwner.reopenRecentlyClosedItem(item)
    }

    func reopenAllWindowsFromLastSession() {
        recentlyClosedRestoreOwner.reopenAllWindowsFromLastSession()
    }

    func clearAllHistoryFromMenu() {
        historyMenuOwner.clearAllHistoryFromMenu()
    }

    func handleWindowWillClose(_ windowId: UUID) {
        windowHistorySessionOwner.handleWindowWillClose(windowId)
    }

    func refreshLastSessionWindowsStore(excludingWindowID: UUID?) {
        windowHistorySessionOwner.refreshLastSessionWindowsStore(excludingWindowID: excludingWindowID)
    }

    func reopenWindow(from snapshot: WindowSessionSnapshot) async {
        await historyMenuOwner.reopenWindow(from: snapshot)
    }

    func currentRegularWindowSnapshots(
        excludingWindowID: UUID?
    ) -> [LastSessionWindowSnapshot] {
        windowHistorySessionOwner.currentRegularWindowSnapshots(excludingWindowID: excludingWindowID)
    }

    func windowDisplayTitle(for windowState: BrowserWindowState) -> String {
        if let currentTab = currentTab(for: windowState) {
            return currentTab.name
        }
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace.name
        }
        return "Window"
    }
}
