import AppKit
import Foundation

enum TabFaviconStore {
    private static let manualOverridesLock = NSLock()
    private static var manualOverrides: [String: NSImage] = [:]

    static func getCachedImage(forDocumentURL url: URL) -> NSImage? {
        if let key = SumiFaviconResolver.cacheKey(for: url),
           let manual = withManualOverrides({ $0[key] }) {
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
        if let manual = withManualOverrides({ $0[key] }) {
            return manual
        }
        return withManager { $0.image(forLookupKey: key) }
    }

    private static func withManualOverrides<T>(_ body: (inout [String: NSImage]) -> T) -> T {
        manualOverridesLock.lock()
        defer { manualOverridesLock.unlock() }
        return body(&manualOverrides)
    }

    private static func withManager<T>(_ body: @MainActor (FaviconManager) -> T) -> T {
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
}
