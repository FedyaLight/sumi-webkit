import Foundation

@MainActor
final class TabEphemeralLifecycleOwner {
    private let prepareTabForRuntime: @MainActor (Tab) -> Void
    private let faviconService: @MainActor () -> any BrowserFaviconServicing
    private let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
    private let visitedLinkStore: @MainActor () -> any BrowserVisitedLinkStoreManaging

    init(
        prepareTabForRuntime: @escaping @MainActor (Tab) -> Void,
        faviconService: @escaping @MainActor () -> any BrowserFaviconServicing,
        faviconImageService: @escaping @MainActor () -> any BrowserFaviconImageServicing,
        visitedLinkStore: @escaping @MainActor () -> any BrowserVisitedLinkStoreManaging
    ) {
        self.prepareTabForRuntime = prepareTabForRuntime
        self.faviconService = faviconService
        self.faviconImageService = faviconImageService
        self.visitedLinkStore = visitedLinkStore
    }

    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let nextIndex = windowState.ephemeralTabs.map(\.index).max().map { $0 + 1 } ?? 0
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: nextIndex,
            faviconService: faviconService(),
            faviconImageService: faviconImageService(),
            visitedLinkStore: visitedLinkStore()
        )
        newTab.profileId = profile.id
        prepareTabForRuntime(newTab)

        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id

        RuntimeDiagnostics.emit("🔒 [TabEphemeralLifecycleOwner] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")

        return newTab
    }
}
