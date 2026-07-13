//
//  PinnedSplitPlaceholderTile.swift
//  Sumi
//

import SwiftUI

struct PinnedSplitPlaceholderTile: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let isSelected: Bool
    let accessibilityID: String
    let isAppKitInteractionEnabled: Bool
    let onActivate: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isTileHovered = false
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        let resolvedFavicon = currentLoadedStoredFavicon ?? pin.storedFaviconImage(
            partition: faviconPartition,
            imageReader: faviconImageReader
        )
        let resolvedChromeTemplateSystemImageName = currentLoadedStoredFavicon == nil
            ? pin.storedChromeTemplateSystemImageName(
                for: faviconPartition,
                imageReader: faviconImageReader
            )
            : nil

        PinnedTileVisual(
            tabIcon: resolvedFavicon,
            chromeTemplateSystemImageName: resolvedChromeTemplateSystemImageName,
            presentationState: isSelected ? .visuallySelected : .liveBackgrounded,
            isHovered: displayIsHovered,
            showsSplitGroupOutline: true,
            faviconOpacity: 1,
            accentSourceURL: pin.launchURL,
            accentSourcePartition: faviconPartition,
            faviconImageReader: faviconImageReader
        )
        .frame(maxWidth: .infinity)
        .frame(height: PinnedTileMetrics.height)
        .frame(minWidth: PinnedTileMetrics.minWidth)
        .contentShape(
            RoundedRectangle(
                cornerRadius: sumiSettings.resolvedCornerRadius(PinnedTileMetrics.cornerRadius),
                style: .continuous
            )
        )
        .onTapGesture(perform: onActivate)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "split placeholder")
        .sidebarDDGHover($isTileHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isAppKitInteractionEnabled,
            sourceID: accessibilityID,
            action: onActivate
        )
        .shadow(
            color: isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: isSelected ? 2 : 0,
            y: isSelected ? 1 : 0
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            storedFaviconLoader.invalidateIfNeeded(for: notification, launchURL: pin.launchURL)
        }
    }

    private var displayIsHovered: Bool {
        SidebarHoverChrome.displayHover(
            isTileHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(for: pin.launchURL)
    }

    private var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
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
