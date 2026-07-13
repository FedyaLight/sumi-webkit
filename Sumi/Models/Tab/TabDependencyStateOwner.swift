@MainActor
final class TabDependencyStateOwner {
    weak var sumiSettings: SumiSettingsService?

    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    init(
        faviconService: any BrowserFaviconServicing,
        faviconCapabilities: BrowserFaviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging
    ) {
        self.faviconService = faviconService
        self.faviconCapabilities = faviconCapabilities
        self.visitedLinkStore = visitedLinkStore
    }
}
