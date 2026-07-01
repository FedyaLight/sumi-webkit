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
    func partition(profile: Profile?) -> SumiFaviconPartition { .regular(profile?.id) }
    func invalidateSite(domain _: String, profile _: Profile?) { /* No-op. */ }
    func syncShortcutPins(_ _: [ShortcutPin]) { /* No-op. */ }
    func syncBookmarks(_ _: [SumiBookmark], partition _: SumiFaviconPartition) { /* No-op. */ }
    func clearFaviconPartition(for _: Profile) { /* No-op. */ }

    #if DEBUG
    func drainRuntimeTasksForTests(cancel _: Bool) async { /* No-op. */ }
    #endif
}

private final class FakeTabDependencyFaviconImageService: BrowserFaviconImageServicing {
    func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? { nil }
    func cachedSelection(for _: URL, partition _: SumiFaviconPartition) -> SumiStoredFaviconSelection? { nil }
    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        nil
    }

    @MainActor
    func ingestVisibleTabDiscovery(
        links _: [SumiFaviconDiscoveredLink],
        documentURL _: URL,
        baseURL _: URL?,
        partition _: SumiFaviconPartition,
        webView _: WKWebView?,
        aliasPageURLs _: [URL]
    ) async -> NSImage? {
        nil
    }

    func scheduleColdFetch(
        for _: URL,
        partition _: SumiFaviconPartition,
        priority _: SumiFaviconFetchPriority
    ) { /* No-op. */ }

    func ingestLocalExtensionIcon(
        fileURL _: URL,
        documentURL _: URL,
        partition _: SumiFaviconPartition,
        context _: SumiFaviconDisplayContext
    ) async -> NSImage? {
        nil
    }
}

@MainActor
private final class FakeTabDependencyVisitedLinkStore: BrowserVisitedLinkStoreManaging {
    func replaceVisitedLinks(_ _: [URL], for _: UUID) { /* No-op. */ }
    func applyStore(to _: WKWebViewConfiguration, for _: Profile) { /* No-op. */ }
    func applyStore(to _: WKWebViewConfiguration, profileId _: UUID) { /* No-op. */ }
    func applyStoreFromSourceIfAvailable(
        to _: WKWebViewConfiguration,
        source _: WKWebViewConfiguration?
    ) { /* No-op. */ }
    func enableVisitedLinkRecording(on _: WKWebView) { /* No-op. */ }
    func recordVisitedLink(
        _ _: URL,
        for _: Profile,
        sourceConfiguration _: WKWebViewConfiguration?
    ) { /* No-op. */ }
    func preloadVisitedLinks(_ _: [URL], for _: UUID) { /* No-op. */ }
    func discardStore(for _: UUID) { /* No-op. */ }
}
