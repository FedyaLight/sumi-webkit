//
//  PinnedTile.swift
//  Sumi
//

import SwiftUI

struct PinnedTile: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let essentialBackdropReader: any BrowserEssentialBackdropReading
    let presentationState: ShortcutPresentationState
    let liveTab: Tab?
    let essentialRuntimeState: SumiEssentialRuntimeState?
    let accessibilityID: String
    let onActivate: () -> Void
    let onUnload: () -> Void
    let contextMenuActions: EssentialTileContextMenuActions
    let dragIsEnabled: Bool
    let isAppKitInteractionEnabled: Bool

    var body: some View {
        Group {
            if let liveTab {
                LivePinnedTileContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
                    essentialBackdropReader: essentialBackdropReader,
                    liveTab: liveTab,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
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
                    essentialBackdropReader: essentialBackdropReader,
                    presentationState: presentationState,
                    essentialRuntimeState: essentialRuntimeState,
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
    onActivate: (() -> Void)? = nil,
    isEnabled: Bool = true
) -> SidebarDragSourceConfiguration {
    SidebarDragSourceConfiguration(
        item: SumiDragItem.shortcutPin(
            pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: .essentials,
        previewKind: .essentialsTile,
        previewIcon: previewIcon,
        previewBackdrop: previewBackdrop,
        chromeTemplateSystemImageName: chromeTemplateSystemImageName,
        previewPresentationState: previewPresentationState,
        exclusionZones: exclusionZones,
        onActivate: onActivate,
        isEnabled: isEnabled
    )
}
