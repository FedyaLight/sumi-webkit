import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class TabFaviconRuntime {
    private var resolvedCacheKey: String?
    private var tabExtension: FaviconsTabExtension?
    private var cancellables: Set<AnyCancellable> = []

    @discardableResult
    func applyCachedFaviconOrPlaceholder(
        for url: URL,
        tab: Tab,
        allowCacheLookup: Bool = true
    ) -> Bool {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: url)
        let partition = tab.faviconService.partition(profile: tab.resolveProfile())

        if SumiSurface.isSettingsSurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        if SumiSurface.isHistorySurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        if SumiSurface.isBookmarksSurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        guard allowCacheLookup,
              let referenceKey,
              let image = TabFaviconStore.getCachedImage(
                forReferenceKey: referenceKey,
                partition: partition,
                context: .tabSidebar,
                faviconImageService: tab.faviconImageService
              )
        else {
            if resolvedCacheKey == referenceKey,
               !tab.faviconIsTemplateGlobePlaceholder {
                return false
            }
            tab.favicon = defaultFavicon
            tab.faviconIsTemplateGlobePlaceholder = true
            return false
        }

        tab.favicon = SwiftUI.Image(nsImage: image)
        tab.faviconIsTemplateGlobePlaceholder = false
        resolvedCacheKey = referenceKey
        return true
    }

    func fetchFaviconForVisiblePresentation(tab: Tab) async {
        guard tab.faviconIsTemplateGlobePlaceholder else { return }

        let requestedURL = tab.url
        if applyCachedFaviconOrPlaceholder(for: requestedURL, tab: tab) {
            return
        }

        let partition = tab.faviconService.partition(profile: tab.resolveProfile())
        if let image = await loadExtensionPageFavicon(
            for: requestedURL,
            partition: partition,
            tab: tab
        ),
           !Task.isCancelled,
           tab.url == requestedURL {
            tab.favicon = SwiftUI.Image(nsImage: image)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        if let image = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: requestedURL,
            partition: partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip,
            faviconImageService: tab.faviconImageService
        ),
           !Task.isCancelled,
           tab.url == requestedURL {
            tab.favicon = SwiftUI.Image(nsImage: image)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        loadCachedFaviconFromExtension()
    }

    func ensureExtension(tab: Tab, using scriptsProvider: SumiFaviconUserScripts) {
        cancellables = []

        let extensionInstance = FaviconsTabExtension(
            scriptsPublisher: Just(scriptsProvider).eraseToAnyPublisher(),
            tab: tab,
            faviconService: tab.faviconService,
            faviconImageService: tab.faviconImageService
        )
        tabExtension = extensionInstance
        extensionInstance.loadCachedFavicon(previousURL: nil, error: nil)

        var subscriptions = cancellables
        extensionInstance.faviconPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tab] (image: NSImage?) in
                guard let self, let tab, let image else { return }
                let currentURL = tab.existingWebView?.url ?? tab.url
                guard let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: currentURL) else { return }
                tab.favicon = SwiftUI.Image(nsImage: image)
                tab.faviconIsTemplateGlobePlaceholder = false
                self.resolvedCacheKey = referenceKey
            }
            .store(in: &subscriptions)
        cancellables = subscriptions
    }

    func loadCachedFaviconFromExtension(previousURL: URL? = nil, error: Error? = nil) {
        tabExtension?.loadCachedFavicon(previousURL: previousURL, error: error)
    }

    private func loadExtensionPageFavicon(
        for url: URL,
        partition: SumiFaviconPartition,
        tab: Tab
    ) async -> NSImage? {
        guard ExtensionUtils.isExtensionOwnedURL(url) else { return nil }
        let installedExtensions = tab.faviconExtensionRuntime.installedExtensions()
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
            context: .tabSidebar,
            faviconImageService: tab.faviconImageService
        )
    }
}
