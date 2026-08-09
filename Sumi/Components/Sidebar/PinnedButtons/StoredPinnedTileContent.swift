//
//  StoredPinnedTileContent.swift
//  Sumi
//

import SwiftUI

struct StoredPinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let favoriteBackdropReader: any BrowserFavoriteBackdropReading
    let presentationState: ShortcutPresentationState
    let favoriteRuntimeState: SumiFavoriteRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: FavoriteTileContextMenuActions
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

    var body: some View {
        let resolvedTitle = pin.preferredDisplayTitle
        let resolvedFavicon = currentLoadedStoredFavicon
            ?? Image(systemName: SumiPersistentGlyph.launcherSystemImageFallback)
        let glyphText = pin.glyphText
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? (pin.chromeTemplateSystemImageName
                ?? SumiPersistentGlyph.launcherSystemImageFallback)
            : nil
        PinnedTabView(
            tabIcon: resolvedFavicon,
            glyphText: glyphText,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: nil,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: resolvedFavicon,
                previewBackdrop: cachedFavoriteBackdrop,
                chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                exclusionZones: dragExclusionZones,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            showsSplitGroupOutline: favoriteRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            favoriteBackdropReader: favoriteBackdropReader
        )
        .help(resolvedTitle)
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] { [] }

    private var currentLoadedStoredFavicon: Image? {
        faviconImageStore.image(
            for: pin.launchURL,
            partition: faviconPartition
        )
    }

    private var cachedFavoriteBackdrop: Image? {
        favoriteBackdropReader.cachedBackdrop(
            for: pin.launchURL,
            partition: faviconPartition
        ).map(Image.init(nsImage:))
    }

    private var storedFaviconLoadKey: String {
        faviconImageStore.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        await faviconImageStore.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            imageReader: faviconImageReader
        )
    }
}
