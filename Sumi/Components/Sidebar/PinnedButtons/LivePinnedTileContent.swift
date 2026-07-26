//
//  LivePinnedTileContent.swift
//  Sumi
//

import SwiftUI
import SumiDomain

struct LivePinnedTileContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let essentialBackdropReader: any BrowserEssentialBackdropReading
    @ObservedObject var liveTab: Tab
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
        let resolvedTitle = pin.resolvedDisplayTitle(liveTab: liveTab)
        let glyphText = pin.glyphText
        let launcherFavicon = currentCachedStoredFavicon
        let resolvedFavicon = launcherFavicon ?? liveTab.favicon
        let chromeTemplateSystemImageName = pin.chromeTemplateSystemImageName
            ?? Self.chromeTemplateSystemImageName(
                for: liveTab,
                hasLauncherFavicon: launcherFavicon != nil
            )
        PinnedTabView(
            tabIcon: resolvedFavicon,
            glyphText: glyphText,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            presentationState: presentationState,
            liveTab: liveTab,
            dragSourceConfiguration: makePinnedTileDragSourceConfiguration(
                pin: pin,
                resolvedTitle: resolvedTitle,
                previewIcon: resolvedFavicon,
                previewBackdrop: cachedEssentialBackdrop,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
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

    private static func chromeTemplateSystemImageName(
        for liveTab: Tab,
        hasLauncherFavicon: Bool
    ) -> String? {
        if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if hasLauncherFavicon {
            return nil
        }
        if liveTab.faviconIsTemplateGlobePlaceholder {
            return SumiPersistentGlyph.launcherSystemImageFallback
        }
        return nil
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] {
        var zones: [SidebarDragSourceExclusionZone] = []

        if liveTab.audioState.showsTabAudioButton {
            zones.append(.topLeadingSquare(size: 22, inset: 6))
        }

        return zones
    }

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

    private var currentCachedStoredFavicon: Image? {
        currentLoadedStoredFavicon ?? ShortcutPin.cachedLaunchFavicon(
            for: pin.launchURL,
            partition: faviconPartition,
            imageReader: faviconImageReader
        )
    }

    private var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isEnabled: pin.iconAsset == nil,
            disabledID: pin.id.uuidString
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        guard pin.iconAsset == nil else { return }

        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            imageReader: faviconImageReader,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }
}
