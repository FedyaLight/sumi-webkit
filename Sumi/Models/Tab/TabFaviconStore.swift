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
        context: SumiFaviconDisplayContext = .tabSidebar
    ) -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return cachedImage(
            forDocumentURL: url,
            partition: partition,
            context: context
        )
    }

    @MainActor
    static func loadExtensionPageImage(
        forDocumentURL url: URL,
        iconFileURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        let service = SumiFaviconSystem.shared.service
        let request = SumiPreparedFaviconRequest(
            pageURL: url,
            partition: partition,
            context: context,
            backingScale: SumiFaviconService.defaultBackingScale()
        )
        if let selection = service.cachedSelection(for: url, partition: partition),
           sameFileURL(selection.sourceURL, iconFileURL),
           let image = await service.preparedImage(
               for: request,
               priority: .visibleSidebarOrTabStrip,
               scheduleFetchOnMiss: false
           ) {
            return image
        }

        return await service.ingestLocalExtensionIcon(
            fileURL: iconFileURL,
            documentURL: url,
            partition: partition,
            context: context
        )
    }

    @MainActor
    static func loadCachedLauncherImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition = .regular(nil)
    ) async -> NSImage? {
        await loadCachedDisplayImage(
            forDocumentURL: url,
            partition: partition,
            context: .pinnedLauncher,
            priority: .pinnedLauncher
        )
    }

    @MainActor
    static func loadCachedDisplayImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar,
        priority: SumiFaviconFetchPriority = .visibleSidebarOrTabStrip
    ) async -> NSImage? {
        guard referenceKey(forDocumentURL: url) != nil else {
            return nil
        }

        return await SumiFaviconSystem.shared.service.preparedImage(
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
        context: SumiFaviconDisplayContext = .tabSidebar
    ) -> NSImage? {
        guard let documentURL = documentURL(forReferenceKey: referenceKey) else { return nil }
        return cachedImage(
            forDocumentURL: documentURL,
            partition: partition,
            context: context
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
        context: SumiFaviconDisplayContext
    ) -> NSImage? {
        SumiFaviconSystem.shared.service.cachedPreparedImage(
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
