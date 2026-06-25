import AppKit
import Foundation
import WebKit

enum SumiFaviconResolver {
    @MainActor private static var menuSystemImageCache: [String: NSImage] = [:]

    static func cacheKey(for url: URL) -> String? {
        SumiFaviconLookupKey.cacheKey(for: url)
    }

    @MainActor
    static func menuImage(
        for url: URL?,
        partition: SumiFaviconPartition = .regular(nil)
    ) -> NSImage {
        guard let url else {
            return menuSystemImage("globe")
        }

        if let systemName = systemImageName(for: url) {
            return menuSystemImage(systemName)
        }

        if let image = TabFaviconStore.getCachedImage(
            forDocumentURL: url,
            partition: partition,
            context: .menu
        ) {
            return image
        }

        return menuSystemImage("globe")
    }

    @MainActor
    static func menuSystemImage(_ systemName: String) -> NSImage {
        if let cached = menuSystemImageCache[systemName] {
            return cached
        }

        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage(size: .zero)
        image.size = NSSize(width: 16, height: 16)
        menuSystemImageCache[systemName] = image
        return image
    }

    @MainActor
    static func image(
        for url: URL,
        partition: SumiFaviconPartition = .regular(nil),
        webView: WKWebView? = nil
    ) async -> NSImage? {
        if let image = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: url,
            partition: partition,
            context: .tabSidebar,
            priority: webView == nil ? .historyBookmarkVisibleRow : .visibleSidebarOrTabStrip
        ) {
            return image
        }

        SumiFaviconSystem.shared.service.scheduleColdFetch(
            for: url,
            partition: partition,
            priority: webView == nil ? .historyBookmarkVisibleRow : .visibleSidebarOrTabStrip
        )
        return nil
    }

    private static func systemImageName(for url: URL) -> String? {
        if SumiSurface.isSettingsSurfaceURL(url) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if SumiSurface.isHistorySurfaceURL(url) {
            return SumiSurface.historyTabFaviconSystemImageName
        }
        if SumiSurface.isBookmarksSurfaceURL(url) {
            return SumiSurface.bookmarksTabFaviconSystemImageName
        }
        return nil
    }
}
