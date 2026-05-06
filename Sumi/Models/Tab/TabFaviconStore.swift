import AppKit
import Foundation

enum TabFaviconStore {
    private static let manualOverrides = ManualFaviconOverrides()

    static func getCachedImage(forDocumentURL url: URL) -> NSImage? {
        if let key = SumiFaviconResolver.cacheKey(for: url),
           let manual = manualOverrides.image(for: key) {
            return manual
        }

        return withManager { manager in
            if let favicon = manager.getCachedFavicon(
                for: url,
                sizeCategory: .small,
                fallBackToSmaller: true
            ) {
                return favicon.image
            }

            guard let host = url.host else { return nil }
            return manager.getCachedFavicon(
                for: host,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.image
        }
    }

    static func getCachedImage(for key: String) -> NSImage? {
        if let manual = manualOverrides.image(for: key) {
            return manual
        }
        return withManager { $0.image(forLookupKey: key) }
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
}
