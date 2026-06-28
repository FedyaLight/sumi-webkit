//
//  Tab+Favicon.swift
//  Sumi
//

import Foundation
import SwiftUI

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

    static func getCachedFavicon(forReferenceKey referenceKey: String) -> SwiftUI.Image? {
        guard let image = TabFaviconStore.getCachedImage(forReferenceKey: referenceKey) else {
            return nil
        }
        return SwiftUI.Image(nsImage: image)
    }

    static func getCachedFavicon(for key: String) -> SwiftUI.Image? {
        getCachedFavicon(forReferenceKey: key)
    }
}
