//
//  PinnedTile.swift
//  Sumi
//

import SwiftUI

struct PinnedTile: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let favoriteBackdropReader: any BrowserFavoriteBackdropReading
    let presentationState: ShortcutPresentationState
    let liveTab: Tab?
    let favoriteRuntimeState: SumiFavoriteRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: FavoriteTileContextMenuActions
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        Group {
            if let liveTab {
                LivePinnedTileContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
                    favoriteBackdropReader: favoriteBackdropReader,
                    liveTab: liveTab,
                    presentationState: presentationState,
                    favoriteRuntimeState: favoriteRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onUnload: onUnload,
                    contextMenuActions: contextMenuActions,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            } else {
                StoredPinnedTileContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
                    favoriteBackdropReader: favoriteBackdropReader,
                    presentationState: presentationState,
                    favoriteRuntimeState: favoriteRuntimeState,
                    accessibilityID: accessibilityID,
                    onActivate: onActivate,
                    onUnload: onUnload,
                    contextMenuActions: contextMenuActions,
                    dragIsEnabled: dragIsEnabled,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
func makePinnedTileDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    previewIcon: Image?,
    previewBackdrop: Image? = nil,
    chromeTemplateSystemImageName: String? = nil,
    previewPresentationState: ShortcutPresentationState? = nil,
    exclusionZones: [SidebarDragSourceExclusionZone],
    isEnabled: Bool = true
) -> SidebarDragSourceConfiguration {
    SidebarDragSourceConfiguration(
        item: SumiDragItem.shortcutPin(
            pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: .favorite,
        previewKind: .favoriteTile,
        previewIcon: previewIcon,
        previewBackdrop: previewBackdrop,
        chromeTemplateSystemImageName: chromeTemplateSystemImageName,
        previewPresentationState: previewPresentationState,
        exclusionZones: exclusionZones,
        isEnabled: isEnabled
    )
}
