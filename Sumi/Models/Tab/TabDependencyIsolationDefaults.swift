import AppKit
import Foundation
import WebKit

/// Isolation defaults for Models/Managers that must not reach production favicon /
/// visited-link systems. Composition roots (`BrowserManagerDataServices.production`)
/// inject real services; tests may inject fakes or rely on these no-ops.
@MainActor
enum TabDependencyIsolationDefaults {
    static let faviconService: any BrowserFaviconServicing = NoOpBrowserFaviconService()
    static let faviconImageService: any BrowserFaviconImageServicing = NoOpBrowserFaviconImageService()
    static let visitedLinkStore: any BrowserVisitedLinkStoreManaging = NoOpBrowserVisitedLinkStore()
}

@MainActor
private final class NoOpBrowserFaviconService: BrowserFaviconServicing {
    func partition(profile: Profile?) -> SumiFaviconPartition { .regular(profile?.id) }
    func invalidateSite(domain _: String, profile _: Profile?) {}
    func syncShortcutPins(_ _: [ShortcutPin]) {}
    func syncBookmarks(_ _: [SumiBookmark], partition _: SumiFaviconPartition) {}
    func clearFaviconPartition(for _: Profile) {}

#if DEBUG
    func drainRuntimeTasksForTests(cancel _: Bool) async {}
#endif
}

private final class NoOpBrowserFaviconImageService: BrowserFaviconImageServicing {
    func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? { nil }
    func cachedSelection(for _: URL, partition _: SumiFaviconPartition) -> SumiStoredFaviconSelection? { nil }
    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? { nil }

    @MainActor
    func ingestVisibleTabDiscovery(
        links _: [SumiFaviconDiscoveredLink],
        documentURL _: URL,
        baseURL _: URL?,
        partition _: SumiFaviconPartition,
        webView _: WKWebView?,
        aliasPageURLs _: [URL]
    ) async -> NSImage? { nil }

    func scheduleColdFetch(
        for _: URL,
        partition _: SumiFaviconPartition,
        priority _: SumiFaviconFetchPriority
    ) {}

    func ingestLocalExtensionIcon(
        fileURL _: URL,
        documentURL _: URL,
        partition _: SumiFaviconPartition,
        context _: SumiFaviconDisplayContext
    ) async -> NSImage? { nil }
}

@MainActor
private final class NoOpBrowserVisitedLinkStore: BrowserVisitedLinkStoreManaging {
    func replaceVisitedLinks(_ _: [URL], for _: UUID) {}
    func applyStore(to _: WKWebViewConfiguration, for _: Profile) {}
    func applyStore(to _: WKWebViewConfiguration, profileId _: UUID) {}
    func applyStoreFromSourceIfAvailable(
        to _: WKWebViewConfiguration,
        source _: WKWebViewConfiguration?
    ) {}
    func enableVisitedLinkRecording(on _: WKWebView) {}
    func recordVisitedLink(
        _ _: URL,
        for _: Profile,
        sourceConfiguration _: WKWebViewConfiguration?
    ) {}
    func preloadVisitedLinks(_ _: [URL], for _: UUID) {}
    func discardStore(for _: UUID) {}
}
