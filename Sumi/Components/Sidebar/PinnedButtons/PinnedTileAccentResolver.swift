import SwiftUI

enum PinnedTileAccentResolver {
    @MainActor
    static func resolve(
        launchURL: URL?,
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
        if let host = launchURL?.host?.lowercased(), !host.isEmpty {
            let key = SumiFaviconAccentCache.cacheKey(domain: host)
            if let cached = SumiFaviconAccentCache.shared.color(forKey: key) {
                return cached
            }
        }
        return tokens.accent
    }
}
