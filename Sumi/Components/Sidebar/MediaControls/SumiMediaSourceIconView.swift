//
//  SumiMediaSourceIconView.swift
//  Sumi
//

import AppKit
import Foundation
import SwiftUI

struct SumiMediaSourceIconView: View {
    private struct LoadRequest: Equatable {
        let source: SumiBackgroundMediaFaviconSource?
        let refreshGeneration: UInt64
    }

    private struct LoadedFavicon {
        let source: SumiBackgroundMediaFaviconSource
        let image: NSImage
    }

    let sourceHost: String?
    let faviconSource: SumiBackgroundMediaFaviconSource?
    let faviconImageReader: any BrowserFaviconImageReading

    @State private var loadedFavicon: LoadedFavicon?
    @State private var refreshGeneration: UInt64 = 0

    var body: some View {
        Group {
            if let icon = displayedFavicon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else if sourceHost != nil {
                Image(systemName: "globe")
                    .font(SidebarThemeTokens.Typography.MiniPlayer.fallbackSource)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(SidebarThemeTokens.Typography.MiniPlayer.fallbackSource)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: faviconLoadID) {
            await loadFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            guard let source = faviconSource,
                  SumiFaviconNotificationMatcher.update(
                    notification,
                    matches: source.documentURL,
                    partition: source.partition
                  )
            else { return }

            loadedFavicon = nil
            refreshGeneration &+= 1
        }
    }

    @MainActor
    private var displayedFavicon: NSImage? {
        guard let source = faviconSource else { return nil }
        if let image = cachedFavicon(for: source) { return image }
        guard loadedFavicon?.source == source else { return nil }
        return loadedFavicon?.image
    }

    private var faviconLoadID: LoadRequest {
        LoadRequest(source: faviconSource, refreshGeneration: refreshGeneration)
    }

    @MainActor
    private func loadFavicon() async {
        guard let source = faviconSource else {
            loadedFavicon = nil
            return
        }

        if let cachedImage = cachedFavicon(for: source) {
            loadedFavicon = LoadedFavicon(source: source, image: cachedImage)
            return
        }

        let loadedImage = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: source.documentURL,
            partition: source.partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip,
            imageReader: faviconImageReader
        )
        guard !Task.isCancelled else { return }

        if let loadedImage {
            loadedFavicon = LoadedFavicon(source: source, image: loadedImage)
        } else if loadedFavicon?.source != source {
            loadedFavicon = nil
        }
    }

    @MainActor
    private func cachedFavicon(for source: SumiBackgroundMediaFaviconSource) -> NSImage? {
        TabFaviconStore.getCachedImage(
            forDocumentURL: source.documentURL,
            partition: source.partition,
            context: .tabSidebar,
            imageReader: faviconImageReader
        )
    }
}
