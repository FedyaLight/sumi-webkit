//
//  Tab+Favicon.swift
//  Sumi
//

import Foundation
import SwiftUI

extension Tab {
    @MainActor
    private func syncBoundLauncherPinAfterFaviconResolved() {
        guard !faviconIsTemplateGlobePlaceholder else { return }
        browserManager?.tabManager.propagateLauncherFaviconFromLiveTabIfNeeded(self)
    }

    @discardableResult
    func applyCachedFaviconOrPlaceholder(for url: URL) -> Bool {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        if SumiSurface.isSettingsSurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = nil
            syncBoundLauncherPinAfterFaviconResolved()
            return true
        }

        if SumiSurface.isHistorySurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = nil
            syncBoundLauncherPinAfterFaviconResolved()
            return true
        }

        guard let cacheKey = SumiFaviconResolver.cacheKey(for: url),
              let image = TabFaviconStore.getCachedImage(for: cacheKey)
        else {
            if resolvedFaviconCacheKey == SumiFaviconResolver.cacheKey(for: url),
               !faviconIsTemplateGlobePlaceholder {
                return false
            }
            favicon = defaultFavicon
            faviconIsTemplateGlobePlaceholder = true
            return false
        }

        favicon = SwiftUI.Image(nsImage: image)
        faviconIsTemplateGlobePlaceholder = false
        resolvedFaviconCacheKey = cacheKey
        syncBoundLauncherPinAfterFaviconResolved()
        return true
    }

    func fetchFaviconForVisiblePresentation() async {
        guard faviconIsTemplateGlobePlaceholder else { return }
        _ = applyCachedFaviconOrPlaceholder(for: url)
    }

    func fetchAndSetFavicon(for url: URL) async {
        _ = applyCachedFaviconOrPlaceholder(for: url)
    }

    func applyDiscoveredFaviconLinks(
        _ links: [SumiDiscoveredFaviconLink],
        documentURL: URL
    ) async {
        guard let cacheKey = SumiFaviconResolver.cacheKey(for: documentURL),
              let image = await SumiFaviconResolver.shared.image(
                for: documentURL,
                discoveredLinks: links,
                webView: existingWebView
              )
        else {
            return
        }

        await MainActor.run {
            guard self.url == documentURL || self.existingWebView?.url == documentURL else {
                return
            }
            self.favicon = SwiftUI.Image(nsImage: image)
            self.faviconIsTemplateGlobePlaceholder = false
            self.resolvedFaviconCacheKey = cacheKey
            self.syncBoundLauncherPinAfterFaviconResolved()
        }
    }

    static func getCachedFavicon(for key: String) -> SwiftUI.Image? {
        guard let image = TabFaviconStore.getCachedImage(for: key) else {
            return nil
        }
        return SwiftUI.Image(nsImage: image)
    }

    static func clearFaviconCache() {
        TabFaviconStore.clearCache()
        SumiFaviconSystem.shared.manager.clearAll()
    }

    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        TabFaviconStore.getFaviconCacheStats()
    }
}
