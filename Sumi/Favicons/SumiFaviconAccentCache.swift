import AppKit
import SwiftUI

@MainActor
final class SumiFaviconAccentCache {
    static let shared = SumiFaviconAccentCache()

    private var colorsByKey: [String: Color] = [:]

    private init() {
        // Shared cache only.
    }

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
    /// Clears the shared cache. Test-only hook to keep tests isolated from each
    /// other; the cache has no bulk-reset API on the production surface.
    @MainActor
    func resetForTesting() {
        colorsByKey.removeAll()
    }
    #endif
}
