//
//  Tab+Favicon.swift
//  Sumi
//

import AppKit
import Combine
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

        if SumiSurface.isBookmarksSurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
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
        await MainActor.run {
            faviconsTabExtension?.loadCachedFavicon(previousURL: nil, error: nil)
        }
    }

    @MainActor
    func ensureFaviconsTabExtension(using scriptsProvider: SumiDDGFaviconUserScripts) {
        faviconCancellables = []

        let extensionInstance = FaviconsTabExtension(
            scriptsPublisher: Just(scriptsProvider).eraseToAnyPublisher(),
            tab: self,
            faviconManagement: SumiFaviconSystem.shared.manager
        )
        faviconsTabExtension = extensionInstance
        extensionInstance.loadCachedFavicon(previousURL: nil, error: nil)

        var cancellables = faviconCancellables
        extensionInstance.faviconPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (image: NSImage?) in
                guard let self, let image else { return }
                let currentURL = self.existingWebView?.url ?? self.url
                guard let cacheKey = SumiFaviconResolver.cacheKey(for: currentURL) else { return }
                self.favicon = SwiftUI.Image(nsImage: image)
                self.faviconIsTemplateGlobePlaceholder = false
                self.resolvedFaviconCacheKey = cacheKey
                self.syncBoundLauncherPinAfterFaviconResolved()
            }
            .store(in: &cancellables)
        faviconCancellables = cancellables
    }

    static func getCachedFavicon(for key: String) -> SwiftUI.Image? {
        guard let image = TabFaviconStore.getCachedImage(for: key) else {
            return nil
        }
        return SwiftUI.Image(nsImage: image)
    }

    static func clearFaviconCache() {
        TabFaviconStore.clearCache()
        SumiFaviconSystem.shared.clearAll()
    }

}
