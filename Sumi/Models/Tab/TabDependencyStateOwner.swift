import Foundation

struct TabDependencyDataServices {
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    init(
        faviconService: any BrowserFaviconServicing,
        faviconImageService: any BrowserFaviconImageServicing,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging
    ) {
        self.faviconService = faviconService
        self.faviconImageService = faviconImageService
        self.visitedLinkStore = visitedLinkStore
    }
}

@MainActor
final class TabDependencyStateOwner {
    weak var sumiSettings: SumiSettingsService?

    private var dataServicesProvider: (@MainActor () -> TabDependencyDataServices?)?
    private let fallbackFaviconService: any BrowserFaviconServicing
    private let fallbackFaviconImageService: any BrowserFaviconImageServicing
    private let fallbackVisitedLinkStore: any BrowserVisitedLinkStoreManaging

    init(
        faviconService: any BrowserFaviconServicing,
        faviconImageService: any BrowserFaviconImageServicing,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging
    ) {
        self.fallbackFaviconService = faviconService
        self.fallbackFaviconImageService = faviconImageService
        self.fallbackVisitedLinkStore = visitedLinkStore
    }

    func attachDataServicesProvider(_ provider: @MainActor @escaping () -> TabDependencyDataServices?) {
        dataServicesProvider = provider
    }

    var faviconService: any BrowserFaviconServicing {
        dataServicesProvider?()?.faviconService ?? fallbackFaviconService
    }

    var faviconImageService: any BrowserFaviconImageServicing {
        dataServicesProvider?()?.faviconImageService ?? fallbackFaviconImageService
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        dataServicesProvider?()?.visitedLinkStore ?? fallbackVisitedLinkStore
    }
}
