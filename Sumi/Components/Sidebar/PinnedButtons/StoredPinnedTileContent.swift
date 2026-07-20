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
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        let resolvedTitle = pin.preferredDisplayTitle
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFaviconImage(
            partition: faviconPartition,
            imageReader: faviconImageReader
        )
        let glyphText = pin.glyphText
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? (pin.chromeTemplateSystemImageName ?? pin.storedChromeTemplateSystemImageName(
                for: faviconPartition,
                imageReader: faviconImageReader
            ))
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
                onActivate: onActivate,
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
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            storedFaviconLoader.invalidateIfNeeded(
                for: notification,
                launchURL: pin.launchURL,
                partition: faviconPartition
            )
        }
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] { [] }

    private var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(
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
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            imageReader: faviconImageReader,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }
}
