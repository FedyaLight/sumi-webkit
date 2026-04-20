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
            syncBoundLauncherPinAfterFaviconResolved()
            return true
        }

        guard let cacheKey = SumiFaviconResolver.cacheKey(for: url),
              let image = TabFaviconStore.getCachedImage(for: cacheKey)
        else {
            favicon = defaultFavicon
            faviconIsTemplateGlobePlaceholder = true
            return false
        }

        favicon = SwiftUI.Image(nsImage: image)
        faviconIsTemplateGlobePlaceholder = false
        syncBoundLauncherPinAfterFaviconResolved()
        return true
    }

    func fetchFaviconForVisiblePresentation() async {
        guard faviconIsTemplateGlobePlaceholder else { return }
        await fetchAndSetFavicon(for: url)
    }

    func fetchAndSetFavicon(for url: URL) async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        if SumiSurface.isSettingsSurfaceURL(url) {
            await MainActor.run {
                self.favicon = SwiftUI.Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
                self.faviconIsTemplateGlobePlaceholder = false
                self.syncBoundLauncherPinAfterFaviconResolved()
            }
            return
        }

        guard SumiFaviconResolver.cacheKey(for: url) != nil else {
            await MainActor.run {
                self.favicon = defaultFavicon
                self.faviconIsTemplateGlobePlaceholder = true
            }
            return
        }

        if let image = await SumiFaviconResolver.shared.image(for: url) {
            await MainActor.run {
                self.favicon = SwiftUI.Image(nsImage: image)
                self.faviconIsTemplateGlobePlaceholder = false
                self.syncBoundLauncherPinAfterFaviconResolved()
            }
            return
        }

        await MainActor.run {
            self.favicon = defaultFavicon
            self.faviconIsTemplateGlobePlaceholder = true
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
        Task {
            await SumiFaviconResolver.shared.resetTransientState()
        }
    }

    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        TabFaviconStore.getFaviconCacheStats()
    }
}
