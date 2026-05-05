//
//  Tab+Favicon.swift
//  Sumi
//

import AppKit
import Combine
import Foundation
import SwiftUI

extension Tab {
    @discardableResult
    func applyCachedFaviconOrPlaceholder(for url: URL) -> Bool {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        let lookupIdentifier = Self.faviconLookupIdentifier(for: url)

        if SumiSurface.isSettingsSurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = nil
            return true
        }

        if SumiSurface.isHistorySurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = nil
            return true
        }

        if SumiSurface.isBookmarksSurfaceURL(url) {
            favicon = SwiftUI.Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = nil
            return true
        }

        guard SumiFaviconResolver.cacheKey(for: url) != nil,
              let lookupIdentifier,
              let image = TabFaviconStore.getCachedImage(forDocumentURL: url)
        else {
            if resolvedFaviconCacheKey == lookupIdentifier,
               !faviconIsTemplateGlobePlaceholder {
                return false
            }
            favicon = defaultFavicon
            faviconIsTemplateGlobePlaceholder = true
            return false
        }

        favicon = SwiftUI.Image(nsImage: image)
        faviconIsTemplateGlobePlaceholder = false
        resolvedFaviconCacheKey = lookupIdentifier
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
                self.resolvedFaviconCacheKey = Self.faviconLookupIdentifier(for: currentURL) ?? cacheKey
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

    static func getCachedFavicon(forDocumentURL url: URL) -> SwiftUI.Image? {
        guard let image = TabFaviconStore.getCachedImage(forDocumentURL: url) else {
            return nil
        }
        return SwiftUI.Image(nsImage: image)
    }

    private static func faviconLookupIdentifier(for url: URL) -> String? {
        guard SumiFaviconResolver.cacheKey(for: url) != nil else { return nil }
        let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absoluteString.isEmpty ? nil : absoluteString
    }

}
