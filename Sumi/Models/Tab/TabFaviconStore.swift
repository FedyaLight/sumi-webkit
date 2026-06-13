import AppKit
import Foundation

enum TabFaviconStore {
    static func getCachedImage(forDocumentURL url: URL) -> NSImage? {
        getCachedImage(forDocumentURL: url, partition: .regular(nil), context: .tabSidebar)
    }

    static func getCachedImage(
        forDocumentURL url: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar
    ) -> NSImage? {
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            return nil
        }

        return withService { service in
            service.cachedPreparedImage(
                for: SumiPreparedFaviconRequest(
                    pageURL: url,
                    partition: partition,
                    context: context,
                    backingScale: SumiFaviconService.defaultBackingScale()
                )
            )
        }
    }

    static func getCachedImage(forDocumentURL url: URL, maxLongestSide: CGFloat) -> NSImage? {
        getCachedImage(
            forDocumentURL: url,
            partition: .regular(nil),
            context: maxLongestSide <= 22 ? .tabSidebar : .largePreview
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
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
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

    static func getCachedImage(for key: String) -> NSImage? {
        guard let documentURL = SumiFaviconLookupKey.documentURL(for: key) else { return nil }
        return getCachedImage(forDocumentURL: documentURL)
    }

    private static func withService<T: Sendable>(_ body: @MainActor (SumiFaviconService) -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body(SumiFaviconSystem.shared.service)
            }
        }

        var result: T!
        DispatchQueue.main.sync {
            result = body(SumiFaviconSystem.shared.service)
        }
        return result
    }

}
