//
//  StoredPinnedTileContent.swift
//  Sumi
//

import SwiftUI

struct StoredPinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let essentialBackdropReader: any BrowserEssentialBackdropReading
    let presentationState: ShortcutPresentationState
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: EssentialTileContextMenuActions
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
                previewBackdrop: cachedEssentialBackdrop,
                chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
                previewPresentationState: presentationState,
                exclusionZones: dragExclusionZones,
                isEnabled: dragIsEnabled
            ),
            accessibilityID: accessibilityID,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            showsUnloadIndicator: false,
            showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true,
            supportsMiddleClickUnload: true,
            contextMenuEntries: { contextMenuActions.entries() },
            action: onActivate,
            onUnload: onUnload,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            essentialBackdropReader: essentialBackdropReader
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

    private var cachedEssentialBackdrop: Image? {
        essentialBackdropReader.cachedBackdrop(
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
