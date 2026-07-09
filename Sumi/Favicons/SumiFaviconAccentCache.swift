import AppKit
import SwiftUI

@MainActor
protocol SumiFaviconAccentCaching: AnyObject {
    func color(forKey key: String) -> Color?
    func store(color: Color, forKey key: String)
    func invalidate(forKey key: String)
    func invalidate(domain: String)
}

@MainActor
enum SumiFaviconAccentCacheDefaults {
    /// Process-scoped accent cache constructed at first use (no singleton accessor).
    static let cache: any SumiFaviconAccentCaching = SumiFaviconAccentCache()
}

@MainActor
final class SumiFaviconAccentCache: SumiFaviconAccentCaching {
    private var colorsByKey: [String: Color] = [:]

    init() {}

    func color(forKey key: String) -> Color? {
        colorsByKey[key]
    }

    func store(color: Color, forKey key: String) {
        colorsByKey[key] = color
    }

    func invalidate(forKey key: String) {
        colorsByKey.removeValue(forKey: key)
    }

    func invalidate(domain: String) {
        let prefix = "\(domain)|"
        colorsByKey.keys
            .filter { $0.hasPrefix(prefix) || $0 == domain }
            .forEach { colorsByKey.removeValue(forKey: $0) }
    }

    nonisolated static func cacheKey(domain: String, faviconIdentity: String? = nil) -> String {
        if let faviconIdentity, !faviconIdentity.isEmpty {
            return "\(domain)|\(faviconIdentity)"
        }
        return domain
    }

    #if DEBUG
    /// Clears the process-scoped cache. Test-only hook to keep tests isolated from each
    /// other; the cache has no bulk-reset API on the production surface.
    @MainActor
    func resetForTesting() {
        colorsByKey.removeAll()
    }
    #endif
}
