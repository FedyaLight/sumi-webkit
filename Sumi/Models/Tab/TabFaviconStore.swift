import AppKit
import Foundation

enum TabFaviconStore {
    private static let manualOverrides = ManualFaviconOverrides()
    private static let displayImageCache = DisplayImageCache()

    static func getCachedImage(forDocumentURL url: URL) -> NSImage? {
        getCachedImage(
            forDocumentURL: url,
            maxLongestSide: CGFloat(SumiFaviconImagePolicy.maxLauncherDisplayPixelSize)
        )
    }

    static func getCachedImage(forDocumentURL url: URL, maxLongestSide: CGFloat) -> NSImage? {
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            return nil
        }

        let displayCacheKey = displayImageCacheKey(for: url, maxLongestSide: maxLongestSide)
        if let cached = displayImageCache.image(for: displayCacheKey) {
            return cached
        }

        if let key = SumiFaviconResolver.cacheKey(for: url),
           let manual = manualOverrides.image(for: key) {
            let prepared = manual.sumiPreparedDisplayFaviconImage(maxLongestSide: maxLongestSide)
            displayImageCache.setImage(prepared, for: displayCacheKey)
            return prepared
        }

        let baseDomain = url.host.flatMap { SumiRegistrableDomainResolver().registrableDomain(forHost: $0) }
        let image = withManager { manager in
            manager.getCachedDisplayFavicon(
                for: url,
                baseDomain: baseDomain,
                targetPixelSize: maxLongestSide
            )?.image
        }

        return image?.sumiPreparedDisplayFaviconImage(maxLongestSide: maxLongestSide)
    }

    @MainActor
    static func loadCachedLauncherImage(forDocumentURL url: URL) async -> NSImage? {
        await loadCachedDisplayImage(forDocumentURL: url)
    }

    @MainActor
    static func loadCachedDisplayImage(
        forDocumentURL url: URL,
        sizeCategory: Favicon.SizeCategory = .medium,
        maxLongestSide: CGFloat = CGFloat(SumiFaviconImagePolicy.maxLauncherDisplayPixelSize)
    ) async -> NSImage? {
        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            return nil
        }

        let displayCacheKey = displayImageCacheKey(for: url, maxLongestSide: maxLongestSide)
        if let cached = displayImageCache.image(for: displayCacheKey) {
            return cached
        }

        if let key = SumiFaviconResolver.cacheKey(for: url),
           let manual = manualOverrides.image(for: key) {
            let prepared = manual.sumiPreparedDisplayFaviconImage(maxLongestSide: maxLongestSide)
            displayImageCache.setImage(prepared, for: displayCacheKey)
            return prepared
        }

        let manager = SumiFaviconSystem.shared.manager
        let baseDomain = url.host.flatMap { SumiRegistrableDomainResolver().registrableDomain(forHost: $0) }
        guard let image = await manager.loadCachedDisplayFavicon(
            for: url,
            baseDomain: baseDomain,
            targetPixelSize: maxLongestSide
        )?.image else { return nil }

        let prepared = image.sumiPreparedDisplayFaviconImage(maxLongestSide: maxLongestSide)
        displayImageCache.setImage(prepared, for: displayCacheKey)
        return prepared
    }

    static func getCachedImage(for key: String) -> NSImage? {
        if let manual = manualOverrides.image(for: key) {
            return manual
        }
        guard let documentURL = SumiFaviconLookupKey.documentURL(for: key) else { return nil }
        return getCachedImage(forDocumentURL: documentURL)
    }

    private static func displayImageCacheKey(for url: URL, maxLongestSide: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxLongestSide.rounded(.up)))"
    }

    private static func withManager<T: Sendable>(_ body: @MainActor (FaviconManager) -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                body(SumiFaviconSystem.shared.manager)
            }
        }

        var result: T!
        DispatchQueue.main.sync {
            result = body(SumiFaviconSystem.shared.manager)
        }
        return result
    }

    private final class ManualFaviconOverrides: @unchecked Sendable {
        private let lock = NSLock()
        private var images: [String: NSImage] = [:]

        func image(for key: String) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return images[key]
        }
    }

    private final class DisplayImageCache: @unchecked Sendable {
        private let cache = NSCache<NSString, NSImage>()
        private var observer: NSObjectProtocol?

        init() {
            cache.countLimit = 96
            cache.totalCostLimit = 8 * 1024 * 1024
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
            cache.setObject(image, forKey: key as NSString, cost: image.sumiApproximateBitmapByteCost)
        }
    }
}

private extension NSImage {
    func sumiPreparedDisplayFaviconImage(maxLongestSide: CGFloat) -> NSImage {
        sumiFaviconImageConstrained(maxLongestSide: maxLongestSide)
    }

    var sumiApproximateBitmapByteCost: Int {
        let representationCost = representations
            .map { $0.pixelsWide * $0.pixelsHigh * 4 }
            .max() ?? 0
        if representationCost > 0 {
            return representationCost
        }

        return max(1, Int(size.width * size.height * 4))
    }
}
