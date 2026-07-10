import Foundation

struct TabDependencyDataServices {
    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
}

@MainActor
final class TabDependencyStateOwner {
    weak var sumiSettings: SumiSettingsService?

    private var dataServicesProvider: (@MainActor () -> TabDependencyDataServices?)?
    private let fallbackFaviconService: any BrowserFaviconServicing
    private let fallbackFaviconCapabilities: BrowserFaviconCapabilities
    private let fallbackVisitedLinkStore: any BrowserVisitedLinkStoreManaging

    init(
        faviconService: any BrowserFaviconServicing,
        faviconCapabilities: BrowserFaviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging
    ) {
        self.fallbackFaviconService = faviconService
        self.fallbackFaviconCapabilities = faviconCapabilities
        self.fallbackVisitedLinkStore = visitedLinkStore
    }

    func attachDataServicesProvider(_ provider: @MainActor @escaping () -> TabDependencyDataServices?) {
        dataServicesProvider = provider
    }

    var faviconService: any BrowserFaviconServicing {
        dataServicesProvider?()?.faviconService ?? fallbackFaviconService
    }

    var faviconCapabilities: BrowserFaviconCapabilities {
        dataServicesProvider?()?.faviconCapabilities ?? fallbackFaviconCapabilities
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        dataServicesProvider?()?.visitedLinkStore ?? fallbackVisitedLinkStore
    }
}
