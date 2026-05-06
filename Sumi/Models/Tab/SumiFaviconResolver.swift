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

    @MainActor
    static func image(for url: URL, webView: WKWebView? = nil) async -> NSImage? {
        await SumiFaviconSystem.shared.manager.handleFaviconLinks([], documentUrl: url, webView: webView)?.image
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
    private static let storage = Storage()

    static func image(for key: String) -> NSImage? {
        storage.image(for: key)
    }

    static func setImage(_ image: NSImage, for key: String) {
        storage.setImage(image, for: key)
    }

    private final class Storage: @unchecked Sendable {
        private let cache = NSCache<NSString, NSImage>()
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: .faviconCacheUpdated,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.cache.removeAllObjects()
            }
        }

        func image(for key: String) -> NSImage? {
            _ = observer
            return cache.object(forKey: key as NSString)
        }

        func setImage(_ image: NSImage, for key: String) {
            _ = observer
            cache.setObject(image, forKey: key as NSString)
        }
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
