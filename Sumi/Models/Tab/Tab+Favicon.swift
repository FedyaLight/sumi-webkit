//
//  Tab+Favicon.swift
//  Sumi
//

import Foundation
import SumiDomain

extension Tab {
    func applyFaviconPlaceholderWithoutCache(for url: URL) {
        let systemSymbol: String
        if SumiSurface.isHistorySurfaceURL(url) {
            systemSymbol = SumiSurface.historyTabFaviconSystemImageName
        } else if SumiSurface.isBookmarksSurfaceURL(url) {
            systemSymbol = SumiSurface.bookmarksTabFaviconSystemImageName
        } else {
            systemSymbol = "globe"
        }
        faviconPresentation = .systemSymbol(systemSymbol)
        faviconIsTemplateGlobePlaceholder = systemSymbol == "globe"
    }

    @discardableResult
    func applyCachedFaviconOrPlaceholder(
        for url: URL,
        allowCacheLookup: Bool = true
    ) -> Bool {
        faviconRuntime.applyCachedFaviconOrPlaceholder(
            for: url,
            tab: self,
            allowCacheLookup: allowCacheLookup
        )
    }

    @MainActor
    func fetchFaviconForVisiblePresentation() async {
        await faviconRuntime.fetchFaviconForVisiblePresentation(tab: self)
    }

    @MainActor
    func ensureFaviconsTabExtension(using scriptsProvider: SumiFaviconUserScripts) {
        faviconRuntime.ensureExtension(tab: self, using: scriptsProvider)
    }

    @MainActor
    func refreshFaviconExtensionCache() {
        faviconRuntime.loadCachedFaviconFromExtension()
    }
}
