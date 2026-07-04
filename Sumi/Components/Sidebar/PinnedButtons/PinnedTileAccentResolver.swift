import Foundation
import SwiftUI

enum PinnedTileAccentResolver {
    @MainActor
    static func resolve(
        launchURL: URL?,
        partition: SumiFaviconPartition? = nil,
        glyphText: String?,
        chromeTemplateSystemImageName: String?,
        tokens: ChromeThemeTokens,
        accentCache: any SumiFaviconAccentCaching = SumiFaviconAccentCacheDefaults.cache
    ) -> Color {
        if chromeTemplateSystemImageName != nil {
            return tokens.primaryText
        }
        if glyphText != nil {
            return tokens.accent
        }
        if let cached = cachedAccent(for: launchURL, partition: partition, accentCache: accentCache) {
            return cached
        }
        return tokens.accent
    }

    @MainActor
    static func cachedAccent(
        for launchURL: URL?,
        partition: SumiFaviconPartition?,
        accentCache: any SumiFaviconAccentCaching = SumiFaviconAccentCacheDefaults.cache
    ) -> Color? {
        guard let host = normalizedHost(for: launchURL) else { return nil }

        if let partition {
            let partitionKey = SumiFaviconAccentCache.cacheKey(
                domain: host,
                faviconIdentity: partition.storageComponent
            )
            if let cached = accentCache.color(forKey: partitionKey) {
                return cached
            }
        }

        return accentCache.color(
            forKey: SumiFaviconAccentCache.cacheKey(domain: host)
        )
    }

    @MainActor
    static func storeAccent(
        _ color: Color,
        for launchURL: URL,
        partition: SumiFaviconPartition?,
        accentCache: any SumiFaviconAccentCaching = SumiFaviconAccentCacheDefaults.cache
    ) {
        guard let host = normalizedHost(for: launchURL) else { return }

        if let partition {
            accentCache.store(
                color: color,
                forKey: SumiFaviconAccentCache.cacheKey(
                    domain: host,
                    faviconIdentity: partition.storageComponent
                )
            )
        }
        accentCache.store(
            color: color,
            forKey: SumiFaviconAccentCache.cacheKey(domain: host)
        )
    }

    @MainActor
    static func invalidateAccent(
        for launchURL: URL?,
        accentCache: any SumiFaviconAccentCaching = SumiFaviconAccentCacheDefaults.cache
    ) {
        guard let host = normalizedHost(for: launchURL) else { return }
        accentCache.invalidate(domain: host)
    }

    static func faviconUpdate(_ notification: Notification, matches launchURL: URL?) -> Bool {
        guard let updatedDomain = notification.userInfo?[NSNotification.Name.faviconCacheUpdatedDomainKey] as? String else {
            return true
        }
        guard let host = normalizedHost(for: launchURL) else { return false }
        return host == SumiSiteNormalizer().host(fromRawHost: updatedDomain)
    }

    private static func normalizedHost(for launchURL: URL?) -> String? {
        SumiSiteNormalizer().host(for: launchURL)
    }
}
