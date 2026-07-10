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
        imageReader: any BrowserFaviconImageReading = SumiFaviconProductionSystem.current.runtime.images
    ) -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return cachedImage(
            forDocumentURL: url,
            partition: partition,
            context: context,
            imageReader: imageReader
        )
    }

    @MainActor
    static func loadExtensionPageImage(
        forDocumentURL url: URL,
        iconFileURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        imageReader: any BrowserFaviconImageReading = SumiFaviconProductionSystem.current.runtime.images,
        localIconIngestion: any BrowserFaviconLocalIconIngesting = SumiFaviconProductionSystem.current.runtime.payloadIngestion
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        let request = SumiPreparedFaviconRequest(
            pageURL: url,
            partition: partition,
            context: context,
            backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
        )
        if let selection = imageReader.cachedSelection(for: url, partition: partition),
           sameFileURL(selection.sourceURL, iconFileURL),
           let image = await imageReader.preparedImage(
               for: request,
               priority: .visibleSidebarOrTabStrip,
               scheduleFetchOnMiss: false
           ) {
            return image
        }

        return await localIconIngestion.ingestLocalExtensionIcon(
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
        imageReader: any BrowserFaviconImageReading = SumiFaviconProductionSystem.current.runtime.images
    ) async -> NSImage? {
        await loadCachedDisplayImage(
            forDocumentURL: url,
            partition: partition,
            context: .pinnedLauncher,
            priority: .pinnedLauncher,
            imageReader: imageReader
        )
    }

    @MainActor
    static func loadCachedDisplayImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        priority: SumiFaviconFetchPriority = .visibleSidebarOrTabStrip,
        imageReader: any BrowserFaviconImageReading = SumiFaviconProductionSystem.current.runtime.images
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return await imageReader.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: url,
                partition: partition,
                context: context,
                backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
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
        imageReader: any BrowserFaviconImageReading = SumiFaviconProductionSystem.current.runtime.images
    ) -> NSImage? {
        guard let documentURL = documentURL(forReferenceKey: referenceKey) else { return nil }
        return cachedImage(
            forDocumentURL: documentURL,
            partition: partition,
            context: context,
            imageReader: imageReader
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
        imageReader: any BrowserFaviconImageReading
    ) -> NSImage? {
        imageReader.cachedPreparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: url,
                partition: partition,
                context: context,
                backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
            )
        )
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
