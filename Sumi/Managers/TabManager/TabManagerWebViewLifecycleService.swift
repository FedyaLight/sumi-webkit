import Foundation
import WebKit

@MainActor
struct TabManagerWebViewLifecycleService {
    private let materializeVisibleWebViewIfNeeded: (Tab, BrowserWindowState) -> Void
    private let loadTabHandler: (Tab) -> Void
    private let unloadTabHandler: (Tab) -> Void
    private let requireRemoveAllWebViewsHandler: (Tab, Bool) -> Void
    private let windowIDsTrackingWebViewsProvider: (UUID) -> [UUID]
    private let primaryTrackedWindowIdProvider: (UUID) -> UUID?
    private let rebuildLiveWebViewsHandler: (Tab, UUID?, URL?) -> Void
    private let prepareTabHandler: (Tab) -> Void
    private let anyLiveWebViewProvider: (Tab) -> WKWebView?
    private let hasUntrackedOwnedWebViewProvider: (Tab) -> Bool

    init(
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in /* No-op. */ },
        loadTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        unloadTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in /* No-op. */ },
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID] = { _ in [] },
        primaryTrackedWindowId: @escaping (UUID) -> UUID? = { _ in nil },
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void = { _, _, _ in /* No-op. */ },
        prepareTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        anyLiveWebView: @escaping (Tab) -> WKWebView? = { _ in nil },
        hasUntrackedOwnedWebView: @escaping (Tab) -> Bool = { _ in false }
    ) {
        self.materializeVisibleWebViewIfNeeded = materializeVisibleTabWebViewIfNeeded
        self.loadTabHandler = loadTab
        self.unloadTabHandler = unloadTab
        self.requireRemoveAllWebViewsHandler = requireRemoveAllWebViews
        self.windowIDsTrackingWebViewsProvider = windowIDsTrackingWebViews
        self.primaryTrackedWindowIdProvider = primaryTrackedWindowId
        self.rebuildLiveWebViewsHandler = rebuildLiveWebViews
        self.prepareTabHandler = prepareTab
        self.anyLiveWebViewProvider = anyLiveWebView
        self.hasUntrackedOwnedWebViewProvider = hasUntrackedOwnedWebView
    }

    static let inactive = Self()

    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState) {
        materializeVisibleWebViewIfNeeded(tab, windowState)
    }

    func loadTab(_ tab: Tab) {
        loadTabHandler(tab)
    }

    func unloadTab(_ tab: Tab) {
        unloadTabHandler(tab)
    }

    func requireRemoveAllWebViews(for tab: Tab, closeActiveFullscreenMedia: Bool) {
        requireRemoveAllWebViewsHandler(tab, closeActiveFullscreenMedia)
    }

    func windowIDsTrackingWebViews(for tabId: UUID) -> [UUID] {
        windowIDsTrackingWebViewsProvider(tabId)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        primaryTrackedWindowIdProvider(tabId)
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?) {
        rebuildLiveWebViewsHandler(tab, preferredPrimaryWindowId, url)
    }

    func prepareTab(_ tab: Tab) {
        prepareTabHandler(tab)
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        anyLiveWebViewProvider(tab)
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        hasUntrackedOwnedWebViewProvider(tab)
    }
}
