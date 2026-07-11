import AppKit
import WebKit
import SumiDomain

enum HistoryOpenMode {
    case currentTab
    case newTab
    case newWindow
}

/// Open-history-URL / tab / window batching collaborator for `BrowserHistoryNavigationOwner`.
/// Not a BrowserManager lazy Owner — constructed inside the navigation façade.
@MainActor
final class BrowserHistoryOpenOwner {
    private typealias NewWindowRegistrationAwaiter = @MainActor () async -> BrowserWindowState?

    private let activeWindow: @MainActor @Sendable () -> BrowserWindowState?
    private let activePage: @MainActor @Sendable (BrowserWindowState) -> ActivePageResolution?
    private let openNativeBrowserSurface: @MainActor @Sendable (
        SumiNativeBrowserSurfaceKind,
        URL,
        BrowserWindowState,
        UUID?
    ) -> Void
    private let openNewTab: @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab?
    private let loadCurrentPageURL: @MainActor @Sendable (Tab, BrowserWindowState, URL) -> Void
    private let windowIds: @MainActor @Sendable () -> [UUID]
    private let createNewWindow: @MainActor @Sendable () -> Void
    private let awaitNextRegisteredWindow: @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?
    private let scheduleRuntimeStatePersistence: @MainActor @Sendable (Tab) -> Void
    private let schedulePrepareVisibleWebViews: @MainActor @Sendable (BrowserWindowState) -> Void
    private let refreshCompositor: @MainActor @Sendable (BrowserWindowState) -> Void

    init(
        activeWindow: @escaping @MainActor @Sendable () -> BrowserWindowState?,
        activePage: @escaping @MainActor @Sendable (BrowserWindowState) -> ActivePageResolution?,
        openNativeBrowserSurface: @escaping @MainActor @Sendable (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState,
            UUID?
        ) -> Void,
        openNewTab: @escaping @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab?,
        loadCurrentPageURL: @escaping @MainActor @Sendable (Tab, BrowserWindowState, URL) -> Void,
        windowIds: @escaping @MainActor @Sendable () -> [UUID],
        createNewWindow: @escaping @MainActor @Sendable () -> Void,
        awaitNextRegisteredWindow: @escaping @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?,
        scheduleRuntimeStatePersistence: @escaping @MainActor @Sendable (Tab) -> Void,
        schedulePrepareVisibleWebViews: @escaping @MainActor @Sendable (BrowserWindowState) -> Void,
        refreshCompositor: @escaping @MainActor @Sendable (BrowserWindowState) -> Void
    ) {
        self.activeWindow = activeWindow
        self.activePage = activePage
        self.openNativeBrowserSurface = openNativeBrowserSurface
        self.openNewTab = openNewTab
        self.loadCurrentPageURL = loadCurrentPageURL
        self.windowIds = windowIds
        self.createNewWindow = createNewWindow
        self.awaitNextRegisteredWindow = awaitNextRegisteredWindow
        self.scheduleRuntimeStatePersistence = scheduleRuntimeStatePersistence
        self.schedulePrepareVisibleWebViews = schedulePrepareVisibleWebViews
        self.refreshCompositor = refreshCompositor
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? activeWindow() {
            openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
            return
        }

        let awaitNewWindow = createNewWindowRegistrationAwaiter()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await awaitNewWindow()
            else {
                return
            }
            self.openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
        }
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        if let window = activeWindow() {
            openHistoryURL(url, in: window, preferredOpenMode: .currentTab)
        } else {
            openHistoryURLsInNewWindow([url])
        }
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        switch preferredOpenMode {
        case .currentTab:
            if let currentTab = activePage(windowState)?.tab,
               !currentTab.representsSumiEmptySurface {
                if currentTab.representsSumiHistorySurface {
                    replaceNativeHistoryTab(currentTab, with: url, in: windowState)
                } else {
                    loadCurrentPageURL(currentTab, windowState, url)
                }
            } else {
                openForegroundTab(for: url, in: windowState)
            }
        case .newTab:
            openForegroundTab(for: url, in: windowState)
        case .newWindow:
            openHistoryURLsInNewWindow([url])
        }
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        for (index, url) in uniqueURLs.enumerated() {
            let context: BrowserTabOpenContext
            if index == 0 {
                context = .foreground(windowState: windowState)
            } else {
                context = .background(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            }
            guard let tab = openNewTab(url.absoluteString, context) else {
                continue
            }
            tab.name = displayName(for: url)
        }
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        openURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        let awaitNewWindow = createNewWindowRegistrationAwaiter()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await awaitNewWindow()
            else {
                return
            }
            self.openURLsInNewTabs(uniqueURLs, in: targetWindow)
        }
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        openURLsInNewWindow(urls)
    }

    private func openHistoryTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting range: HistoryRange
    ) {
        openNativeBrowserSurface(
            .history,
            SumiSurface.historySurfaceURL(rangeQuery: range.paneQueryValue),
            targetWindow,
            targetWindow.currentSpaceId
        )
    }

    private func openForegroundTab(for url: URL, in windowState: BrowserWindowState) {
        guard let newTab = openNewTab(
            url.absoluteString,
            .foreground(windowState: windowState)
        ) else { return }
        newTab.name = displayName(for: url)
    }

    private func replaceNativeHistoryTab(
        _ tab: Tab,
        with url: URL,
        in windowState: BrowserWindowState
    ) {
        tab.name = displayName(for: url)
        tab.faviconPresentation = .systemSymbol("globe")
        tab.faviconIsTemplateGlobePlaceholder = true
        loadCurrentPageURL(tab, windowState, url)
        windowState.compositorInvalidation.invalidateNativeSurfaceRouting()
        scheduleRuntimeStatePersistence(tab)
        schedulePrepareVisibleWebViews(windowState)
        refreshCompositor(windowState)

        Task { @MainActor [weak tab] in
            guard let tab else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }
    }

    private func createNewWindowRegistrationAwaiter() -> NewWindowRegistrationAwaiter {
        let existingWindowIDs = Set(windowIds())
        createNewWindow()

        return { [awaitNextRegisteredWindow] in
            await awaitNextRegisteredWindow(existingWindowIDs)
        }
    }

    private func displayName(for url: URL) -> String {
        url.host ?? url.absoluteString
    }
}
