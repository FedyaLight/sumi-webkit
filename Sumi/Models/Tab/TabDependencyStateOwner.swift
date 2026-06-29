import Foundation

@MainActor
final class TabDependencyStateOwner {
    weak var browserManager: BrowserManager?
    weak var sumiSettings: SumiSettingsService?

    private let fallbackFaviconService: any BrowserFaviconServicing
    private let fallbackFaviconImageService: any BrowserFaviconImageServicing
    private let fallbackVisitedLinkStore: any BrowserVisitedLinkStoreManaging

    init(
        browserManager: BrowserManager?,
        faviconService: any BrowserFaviconServicing,
        faviconImageService: any BrowserFaviconImageServicing,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging
    ) {
        self.browserManager = browserManager
        self.fallbackFaviconService = faviconService
        self.fallbackFaviconImageService = faviconImageService
        self.fallbackVisitedLinkStore = visitedLinkStore
    }

    var faviconService: any BrowserFaviconServicing {
        browserManager?.dataServices.faviconService ?? fallbackFaviconService
    }

    var faviconImageService: any BrowserFaviconImageServicing {
        browserManager?.dataServices.faviconImageService ?? fallbackFaviconImageService
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        browserManager?.dataServices.visitedLinkStore ?? fallbackVisitedLinkStore
    }
}
