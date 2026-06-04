import AppKit
import SwiftUI

@MainActor
final class SumiFaviconAccentCache {
    static let shared = SumiFaviconAccentCache()

    private var colorsByKey: [String: Color] = [:]

    private init() {}

    func color(forKey key: String) -> Color? {
        colorsByKey[key]
    }

    func store(image: NSImage, forKey key: String) {
        guard let color = SumiFaviconAccentColor.extract(from: image) else { return }
        colorsByKey[key] = color
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

    nonisolated static func storeOffMain(image: NSImage, forKey key: String) {
        guard let color = SumiFaviconAccentColor.extract(from: image) else { return }
        Task { @MainActor in
            shared.store(color: color, forKey: key)
        }
    }
}
