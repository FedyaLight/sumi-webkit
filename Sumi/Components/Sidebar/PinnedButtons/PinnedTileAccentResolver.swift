import Foundation
import SwiftUI

enum PinnedTileAccentResolver {
    @MainActor
    static func resolve(
        launchURL: URL?,
        partition: SumiFaviconPartition? = nil,
        glyphText: String?,
        chromeTemplateSystemImageName: String?,
        tokens: ChromeThemeTokens
    ) -> Color {
        if chromeTemplateSystemImageName != nil {
            return tokens.primaryText
        }
        if glyphText != nil {
            return tokens.accent
        }
        if let cached = cachedAccent(for: launchURL, partition: partition) {
            return cached
        }
        return tokens.accent
    }

    @MainActor
    static func cachedAccent(for launchURL: URL?, partition: SumiFaviconPartition?) -> Color? {
        guard let host = normalizedHost(for: launchURL) else { return nil }

        if let partition {
            let partitionKey = SumiFaviconAccentCache.cacheKey(
                domain: host,
                faviconIdentity: partition.storageComponent
            )
            if let cached = SumiFaviconAccentCache.shared.color(forKey: partitionKey) {
                return cached
            }
        }

        return SumiFaviconAccentCache.shared.color(
            forKey: SumiFaviconAccentCache.cacheKey(domain: host)
        )
    }

    @MainActor
    static func storeAccent(_ color: Color, for launchURL: URL, partition: SumiFaviconPartition?) {
        guard let host = normalizedHost(for: launchURL) else { return }

        if let partition {
            SumiFaviconAccentCache.shared.store(
                color: color,
                forKey: SumiFaviconAccentCache.cacheKey(
                    domain: host,
                    faviconIdentity: partition.storageComponent
                )
            )
        }
        SumiFaviconAccentCache.shared.store(
            color: color,
            forKey: SumiFaviconAccentCache.cacheKey(domain: host)
        )
    }

    @MainActor
    static func invalidateAccent(for launchURL: URL?) {
        guard let host = normalizedHost(for: launchURL) else { return }
        SumiFaviconAccentCache.shared.invalidate(domain: host)
    }

    static func faviconUpdate(_ notification: Notification, matches launchURL: URL?) -> Bool {
        guard let updatedDomain = notification.userInfo?[NSNotification.Name.faviconCacheUpdatedDomainKey] as? String else {
            return true
        }
        guard let host = normalizedHost(for: launchURL) else { return false }
        return host == updatedDomain.lowercased()
    }

    private static func normalizedHost(for launchURL: URL?) -> String? {
        guard let host = launchURL?.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
