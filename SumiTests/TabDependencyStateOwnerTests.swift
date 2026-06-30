import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabDependencyStateOwnerTests: XCTestCase {
    func testUsesFallbackServicesWithoutProvider() {
        let fallback = makeServices()
        let owner = makeOwner(fallback: fallback)

        assertServices(owner, identicalTo: fallback)
    }

    func testUsesInjectedDataServicesProviderWhenAvailable() {
        let fallback = makeServices()
        let injected = makeServices()
        let owner = makeOwner(fallback: fallback)

        owner.attachDataServicesProvider { injected.dataServices }

        assertServices(owner, identicalTo: injected)
    }

    func testFallsBackWhenInjectedDataServicesProviderReturnsNil() {
        let fallback = makeServices()
        let owner = makeOwner(fallback: fallback)

        owner.attachDataServicesProvider { nil }

        assertServices(owner, identicalTo: fallback)
    }

    private func makeOwner(fallback: Services) -> TabDependencyStateOwner {
        TabDependencyStateOwner(
            faviconService: fallback.faviconService,
            faviconImageService: fallback.faviconImageService,
            visitedLinkStore: fallback.visitedLinkStore
        )
    }

    private func makeServices() -> Services {
        Services(
            faviconService: FakeTabDependencyFaviconService(),
            faviconImageService: FakeTabDependencyFaviconImageService(),
            visitedLinkStore: FakeTabDependencyVisitedLinkStore()
        )
    }

    private func assertServices(
        _ owner: TabDependencyStateOwner,
        identicalTo expected: Services,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertIdentical(owner.faviconService as AnyObject, expected.faviconService, file: file, line: line)
        XCTAssertIdentical(owner.faviconImageService as AnyObject, expected.faviconImageService, file: file, line: line)
        XCTAssertIdentical(owner.visitedLinkStore as AnyObject, expected.visitedLinkStore, file: file, line: line)
    }

    private struct Services {
        let faviconService: FakeTabDependencyFaviconService
        let faviconImageService: FakeTabDependencyFaviconImageService
        let visitedLinkStore: FakeTabDependencyVisitedLinkStore

        var dataServices: TabDependencyDataServices {
            TabDependencyDataServices(
                faviconService: faviconService,
                faviconImageService: faviconImageService,
                visitedLinkStore: visitedLinkStore
            )
        }
    }
}

@MainActor
private final class FakeTabDependencyFaviconService: BrowserFaviconServicing {
    func partition(profile: Profile?) -> SumiFaviconPartition { fatalError("Not needed") }
    func invalidateSite(domain: String, profile: Profile?) {}
    func syncShortcutPins(_ pins: [ShortcutPin]) {}
    func syncBookmarks(_ bookmarks: [SumiBookmark], partition: SumiFaviconPartition) {}
    func clearFaviconPartition(for profile: Profile) {}

    #if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async {}
    #endif
}

private final class FakeTabDependencyFaviconImageService: BrowserFaviconImageServicing {
    func cachedPreparedImage(for request: SumiPreparedFaviconRequest) -> NSImage? { nil }
    func cachedSelection(for pageURL: URL, partition: SumiFaviconPartition) -> SumiStoredFaviconSelection? { nil }
    func preparedImage(
        for request: SumiPreparedFaviconRequest,
        priority: SumiFaviconFetchPriority,
        scheduleFetchOnMiss: Bool
    ) async -> NSImage? {
        nil
    }

    @MainActor
    func ingestVisibleTabDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL]
    ) async -> NSImage? {
        nil
    }

    func scheduleColdFetch(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    ) {}

    func ingestLocalExtensionIcon(
        fileURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext
    ) async -> NSImage? {
        nil
    }
}

@MainActor
private final class FakeTabDependencyVisitedLinkStore: BrowserVisitedLinkStoreManaging {
    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID) {}
    func applyStore(to configuration: WKWebViewConfiguration, for profile: Profile) {}
    func applyStore(to configuration: WKWebViewConfiguration, profileId: UUID) {}
    func applyStoreFromSourceIfAvailable(
        to configuration: WKWebViewConfiguration,
        source: WKWebViewConfiguration?
    ) {}
    func enableVisitedLinkRecording(on webView: WKWebView) {}
    func recordVisitedLink(
        _ url: URL,
        for profile: Profile,
        sourceConfiguration: WKWebViewConfiguration?
    ) {}
    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID) {}
    func discardStore(for profileId: UUID) {}
}
