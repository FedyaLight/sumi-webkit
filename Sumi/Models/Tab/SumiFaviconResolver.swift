import AppKit
import Foundation
import WebKit

enum SumiFaviconResolver {
    static func cacheKey(for url: URL) -> String? {
        SumiFaviconLookupKey.cacheKey(for: url)
    }

    static func menuImage(for url: URL?) -> NSImage {
        guard let url else {
            return menuSystemImage("globe")
        }

        if let systemName = systemImageName(for: url) {
            return menuSystemImage(systemName)
        }

        if let cacheKey = cacheKey(for: url),
           let cachedImage = MenuImageCache.image(for: cacheKey) {
            return cachedImage
        }

        if let image = TabFaviconStore.getCachedImage(forDocumentURL: url) {
            let resizedImage = image.sumiMenuResizedToFaviconSize()
            if let cacheKey = cacheKey(for: url) {
                MenuImageCache.setImage(resizedImage, for: cacheKey)
            }
            return resizedImage
        }

        return menuSystemImage("globe")
    }

    static func menuSystemImage(_ systemName: String) -> NSImage {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage(size: .zero)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func image(for url: URL, webView: WKWebView? = nil) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.handleFaviconLinks([], documentUrl: url, webView: webView)?.image
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

private enum MenuImageCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: .faviconCacheUpdated,
        object: nil,
        queue: .main
    ) { _ in
        cache.removeAllObjects()
    }

    static func image(for key: String) -> NSImage? {
        _ = observer
        return cache.object(forKey: key as NSString)
    }

    static func setImage(_ image: NSImage, for key: String) {
        _ = observer
        cache.setObject(image, forKey: key as NSString)
    }
}

private extension NSImage {
    func sumiMenuResizedToFaviconSize() -> NSImage {
        let targetSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        image.unlockFocus()
        return image
    }
}
