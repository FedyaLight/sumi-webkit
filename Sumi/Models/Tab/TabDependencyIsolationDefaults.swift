import AppKit
import Foundation
import WebKit

/// Isolation defaults for `Tab` / `TabManager` construction only.
///
/// Composition roots inject real services.
/// Tests may inject fakes or rely on these no-ops.
@MainActor
enum TabDependencyIsolationDefaults {
    private static let faviconAuthority = NoOpBrowserFaviconService()

    static let faviconService: any BrowserFaviconServicing = faviconAuthority
    static let historyFaviconCleaner: any HistoryFaviconCleaning = faviconAuthority
    static let browsingDataFaviconCleaner: any SumiBrowsingDataFaviconCleaning = faviconAuthority
    static let faviconCapabilities: BrowserFaviconCapabilities = {
        let noOp = NoOpBrowserFaviconCapabilities()
        return BrowserFaviconCapabilities(
            images: noOp,
            liveDiscovery: noOp,
            localIconIngestion: noOp,
            prefetch: noOp
        )
    }()
    private static let visitedLinkAuthority = NoOpBrowserVisitedLinkStore()
    static let visitedLinkStore: any BrowserVisitedLinkStoreManaging = visitedLinkAuthority
    static let historyVisitedLinkStore: any HistoryVisitedLinkStoring = visitedLinkAuthority
    static let privatePartitionResidueCleanup:
        any PrivatePartitionResidueCleaning =
            NoOpPrivatePartitionResidueCleanup()
}

@MainActor
private final class NoOpBrowserFaviconService:
    BrowserFaviconServicing,
    HistoryFaviconCleaning,
    SumiBrowsingDataFaviconCleaning
{
    func partition(profile: Profile?) -> SumiFaviconPartition { .regular() }
    func invalidateSite(domain _: String, profile _: Profile?) {}
    func syncShortcutPins(_ _: [ShortcutPin]) {}
    func syncBookmarks(_ _: [SumiBookmark], partition _: SumiFaviconPartition) {}
    func clearFaviconPartition(for _: Profile) {}
    func burnAfterHistoryClear(savedLogins _: Set<String>) async {}
    func burnDomains(
        _ _: Set<String>,
        remainingHistoryHosts _: Set<String>,
        savedLogins _: Set<String>
    ) async {}
    func invalidateSite(domain _: String, partition _: SumiFaviconPartition) {}

#if DEBUG
    func drainRuntimeTasksForTests(cancel _: Bool) async {}
#endif
}

private final class NoOpBrowserFaviconCapabilities:
    BrowserFaviconImageReading,
    BrowserFaviconLiveDiscoveryIngesting,
    BrowserFaviconLocalIconIngesting,
    BrowserFaviconPrefetchScheduling
{
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

    func ingestImportedIcon(
        payload _: Data,
        iconURL _: URL,
        documentURL _: URL,
        partition _: SumiFaviconPartition
    ) async {}
}

@MainActor
private final class NoOpBrowserVisitedLinkStore:
    BrowserVisitedLinkStoreManaging,
    HistoryVisitedLinkStoring
{
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

@MainActor
private final class NoOpPrivatePartitionResidueCleanup:
    PrivatePartitionResidueCleaning {
    func cleanup(profileID _: UUID) {}
}
