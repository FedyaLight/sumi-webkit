//
//  Tab+Favicon.swift
//  Sumi
//

import Foundation

extension Tab {
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
