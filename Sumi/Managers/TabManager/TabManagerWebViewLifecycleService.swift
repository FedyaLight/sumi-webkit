import Foundation

@MainActor
struct TabManagerWebViewLifecycleService {
    private let materializeVisibleTabWebViewIfNeededHandler: (Tab, BrowserWindowState) -> Void
    private let loadTabHandler: (Tab) -> Void
    private let unloadTabHandler: (Tab) -> Void
    private let requireRemoveAllWebViewsHandler: (Tab, Bool) -> Void
    private let windowIDsTrackingWebViewsProvider: (UUID) -> [UUID]
    private let rebuildLiveWebViewsHandler: (Tab, UUID?, URL?) -> Void
    private let prepareTabHandler: (Tab) -> Void

    init(
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
        loadTab: @escaping (Tab) -> Void = { _ in },
        unloadTab: @escaping (Tab) -> Void = { _ in },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID] = { _ in [] },
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void = { _, _, _ in },
        prepareTab: @escaping (Tab) -> Void = { _ in }
    ) {
        self.materializeVisibleTabWebViewIfNeededHandler = materializeVisibleTabWebViewIfNeeded
        self.loadTabHandler = loadTab
        self.unloadTabHandler = unloadTab
        self.requireRemoveAllWebViewsHandler = requireRemoveAllWebViews
        self.windowIDsTrackingWebViewsProvider = windowIDsTrackingWebViews
        self.rebuildLiveWebViewsHandler = rebuildLiveWebViews
        self.prepareTabHandler = prepareTab
    }

    static let inactive = Self()

    func materializeVisibleTabWebViewIfNeeded(_ tab: Tab, in windowState: BrowserWindowState) {
        materializeVisibleTabWebViewIfNeededHandler(tab, windowState)
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

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(for tab: Tab, preferredPrimaryWindowId: UUID?, load url: URL?) {
        rebuildLiveWebViewsHandler(tab, preferredPrimaryWindowId, url)
    }

    func prepareTab(_ tab: Tab) {
        prepareTabHandler(tab)
    }
}
