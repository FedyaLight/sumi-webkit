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
    func applyCachedFaviconOrPlaceholder(
        for url: URL,
        allowCacheLookup: Bool = true
    ) -> Bool {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: url)
        let partition = SumiFaviconSystem.shared.partition(profile: resolveProfile())

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

        guard allowCacheLookup,
              let referenceKey,
              let image = TabFaviconStore.getCachedImage(
                forReferenceKey: referenceKey,
                partition: partition,
                context: .tabSidebar
              )
        else {
            if resolvedFaviconCacheKey == referenceKey,
               !faviconIsTemplateGlobePlaceholder {
                return false
            }
            favicon = defaultFavicon
            faviconIsTemplateGlobePlaceholder = true
            return false
        }

        favicon = SwiftUI.Image(nsImage: image)
        faviconIsTemplateGlobePlaceholder = false
        resolvedFaviconCacheKey = referenceKey
        return true
    }

    @MainActor
    func fetchFaviconForVisiblePresentation() async {
        guard faviconIsTemplateGlobePlaceholder else { return }

        let requestedURL = url
        if applyCachedFaviconOrPlaceholder(for: requestedURL) {
            return
        }

        let partition = SumiFaviconSystem.shared.partition(profile: resolveProfile())
        if let image = await loadExtensionPageFavicon(
            for: requestedURL,
            partition: partition
        ),
           !Task.isCancelled,
           url == requestedURL {
            favicon = SwiftUI.Image(nsImage: image)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        if let image = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: requestedURL,
            partition: partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip
        ),
           !Task.isCancelled,
           url == requestedURL {
            favicon = SwiftUI.Image(nsImage: image)
            faviconIsTemplateGlobePlaceholder = false
            resolvedFaviconCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        faviconsTabExtension?.loadCachedFavicon(previousURL: nil, error: nil)
    }

    @MainActor
    private func loadExtensionPageFavicon(
        for url: URL,
        partition: SumiFaviconPartition
    ) async -> NSImage? {
        guard ExtensionUtils.isExtensionOwnedURL(url) else { return nil }
        let installedExtensions =
            browserManager?.extensionsModule.managerIfLoadedAndEnabled()?.installedExtensions
            ?? browserManager?.extensionSurfaceStore.installedExtensions
            ?? []
        guard let iconPath = ExtensionUtils.iconPath(
            forExtensionOwnedURL: url,
            installedExtensions: installedExtensions
        ) else {
            return nil
        }

        return await TabFaviconStore.loadExtensionPageImage(
            forDocumentURL: url,
            iconFileURL: URL(fileURLWithPath: iconPath),
            partition: partition,
            context: .tabSidebar
        )
    }

    @MainActor
    func ensureFaviconsTabExtension(using scriptsProvider: SumiFaviconUserScripts) {
        faviconCancellables = []

        let extensionInstance = FaviconsTabExtension(
            scriptsPublisher: Just(scriptsProvider).eraseToAnyPublisher(),
            tab: self
        )
        faviconsTabExtension = extensionInstance
        extensionInstance.loadCachedFavicon(previousURL: nil, error: nil)

        var cancellables = faviconCancellables
        extensionInstance.faviconPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (image: NSImage?) in
                guard let self, let image else { return }
                let currentURL = self.existingWebView?.url ?? self.url
                guard let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: currentURL) else { return }
                self.favicon = SwiftUI.Image(nsImage: image)
                self.faviconIsTemplateGlobePlaceholder = false
                self.resolvedFaviconCacheKey = referenceKey
            }
            .store(in: &cancellables)
        faviconCancellables = cancellables
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

    static func getCachedFavicon(forDocumentURL url: URL) -> SwiftUI.Image? {
        guard let image = TabFaviconStore.getCachedImage(forDocumentURL: url) else {
            return nil
        }
        return SwiftUI.Image(nsImage: image)
    }

}
