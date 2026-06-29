import AppKit
import Foundation

enum TabFaviconStore {
    static func referenceKey(forDocumentURL url: URL) -> String? {
        SumiFaviconLookupKey.referenceKey(for: url)
    }

    static func documentURL(forReferenceKey key: String) -> URL? {
        SumiFaviconLookupKey.documentURL(forReferenceKey: key)
    }

    @MainActor
    static func getCachedImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService
    ) -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return cachedImage(
            forDocumentURL: url,
            partition: partition,
            context: context,
            faviconImageService: faviconImageService
        )
    }

    @MainActor
    static func loadExtensionPageImage(
        forDocumentURL url: URL,
        iconFileURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        let request = SumiPreparedFaviconRequest(
            pageURL: url,
            partition: partition,
            context: context,
            backingScale: SumiFaviconService.defaultBackingScale()
        )
        if let selection = faviconImageService.cachedSelection(for: url, partition: partition),
           sameFileURL(selection.sourceURL, iconFileURL),
           let image = await faviconImageService.preparedImage(
               for: request,
               priority: .visibleSidebarOrTabStrip,
               scheduleFetchOnMiss: false
           ) {
            return image
        }

        return await faviconImageService.ingestLocalExtensionIcon(
            fileURL: iconFileURL,
            documentURL: url,
            partition: partition,
            context: context
        )
    }

    @MainActor
    static func loadCachedLauncherImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition = .regular(nil),
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService
    ) async -> NSImage? {
        await loadCachedDisplayImage(
            forDocumentURL: url,
            partition: partition,
            context: .pinnedLauncher,
            priority: .pinnedLauncher,
            faviconImageService: faviconImageService
        )
    }

    @MainActor
    static func loadCachedDisplayImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        priority: SumiFaviconFetchPriority = .visibleSidebarOrTabStrip,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return await faviconImageService.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: url,
                partition: partition,
                context: context,
                backingScale: SumiFaviconService.defaultBackingScale()
            ),
            priority: priority,
            scheduleFetchOnMiss: true
        )
    }

    @MainActor
    static func getCachedImage(for key: String) -> NSImage? {
        getCachedImage(forReferenceKey: key)
    }

    @MainActor
    static func getCachedImage(
        forReferenceKey referenceKey: String,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService
    ) -> NSImage? {
        guard let documentURL = documentURL(forReferenceKey: referenceKey) else { return nil }
        return cachedImage(
            forDocumentURL: documentURL,
            partition: partition,
            context: context,
            faviconImageService: faviconImageService
        )
    }

    @MainActor
    static func getCachedImage(forReferenceKey referenceKey: String) -> NSImage? {
        getCachedImage(forReferenceKey: referenceKey, partition: .regular(nil), context: .tabSidebar)
    }

    @MainActor
    private static func cachedImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext,
        faviconImageService: any BrowserFaviconImageServicing
    ) -> NSImage? {
        faviconImageService.cachedPreparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: url,
                partition: partition,
                context: context,
                backingScale: SumiFaviconService.defaultBackingScale()
            )
        )
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
