//
//  SplitGroupSegment.swift
//  Sumi
//

import SwiftUI

struct SplitGroupSegment: View {
    let groupID: UUID
    let item: SplitGroupSidebarItem
    let spaceId: UUID
    let isDeparting: Bool
    let trailingPadding: CGFloat
    let reservesTrailingAction: Bool
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let dragSourceConfiguration: SidebarDragSourceConfiguration?
    let dragPreviewSourceGeometry: SidebarDragPreviewSourceGeometry?
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onMiddleClick: (() -> Void)?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        SplitGroupSegmentLabel(
            title: item.title,
            trailingPadding: trailingPadding,
            textColor: tokens.primaryText
        ) {
            icon
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: (item.tab != nil || dragSourceConfiguration != nil) && isAppKitInteractionEnabled,
            dragSource: resolvedDragSourceConfiguration,
            primaryAction: onActivate,
            onMiddleClick: onMiddleClick,
            sourceID: rowSourceID,
            entries: contextMenuEntries
        )
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(isDeparting ? 0 : 1)
        .task(id: item.tab?.url) {
            await item.tab?.fetchFaviconForVisiblePresentation()
        }
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .faviconCacheUpdated)
        ) { notification in
            guard let pin = item.pin, pin.iconAsset == nil else { return }
            storedFaviconLoader.invalidateIfNeeded(
                for: notification,
                launchURL: pin.launchURL,
                partition: faviconPartition(for: pin)
            )
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let liveTab = item.tab {
            SplitGroupLiveMemberIcon(
                item: item,
                liveTab: liveTab,
                loadedStoredFavicon: loadedStoredFavicon,
                faviconImageReader: faviconImageReader
            )
        } else {
            SplitGroupResolvedMemberIcon(presentation: iconPresentation)
        }
    }

    private var iconPresentation: SplitGroupMemberIconPresentation {
        SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: loadedStoredFavicon,
            imageReader: faviconImageReader
        )
    }

    private var loadedStoredFavicon: Image? {
        item.pin.flatMap {
            storedFaviconLoader.image(
                for: $0.launchURL,
                partition: faviconPartition(for: $0)
            )
        }
    }

    private var storedFaviconLoadKey: String? {
        guard let pin = item.pin else { return nil }
        return storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition(for: pin),
            isEnabled: pin.iconAsset == nil,
            disabledID: pin.id.uuidString
        )
    }

    @MainActor
    private func loadStoredFavicon() async {
        guard let pin = item.pin, pin.iconAsset == nil else { return }
        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition(for: pin),
            imageReader: faviconImageReader,
            isCurrentLaunchURL: { item.pin?.launchURL == $0 }
        )
    }

    private func faviconPartition(for pin: ShortcutPin) -> SumiFaviconPartition {
        .regular(pin.executionProfileId ?? pin.profileId)
    }

    private var resolvedDragSourceConfiguration: SidebarDragSourceConfiguration? {
        if let dragSourceConfiguration {
            return dragSourceConfiguration.replacingExclusionZones(
                reservesTrailingAction ? [.trailingStrip(32)] : []
            )
            .replacingPreviewSourceGeometry(dragPreviewSourceGeometry)
        }
        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitGroup(
                groupID,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(spaceId),
            previewKind: .row,
            previewIcon: tab.favicon,
            previewSourceGeometry: dragPreviewSourceGeometry,
            exclusionZones: reservesTrailingAction
                ? [.trailingStrip(32)] : [],
            onActivate: onActivate,
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var rowSourceID: String {
        "space-split-member-\(item.stableIDDescription)"
    }

    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}

private struct SplitGroupLiveMemberIcon: View {
    let item: SplitGroupSidebarItem
    @ObservedObject var liveTab: Tab
    let loadedStoredFavicon: Image?
    let faviconImageReader: any BrowserFaviconImageReading

    var body: some View {
        SplitGroupResolvedMemberIcon(
            presentation: SplitGroupMemberIconResolver.resolve(
                item: item,
                loadedStoredFavicon: loadedStoredFavicon,
                imageReader: faviconImageReader
            )
        )
    }
}

private struct SplitGroupResolvedMemberIcon: View {
    let presentation: SplitGroupMemberIconPresentation

    var body: some View {
        Group {
            if let glyph = presentation.glyphText {
                Text(glyph)
                    .font(.system(size: 16))
            } else if let systemName = presentation.systemImageName {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.monochrome)
            } else {
                presentation.image
                    .resizable()
                    .scaledToFit()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 4,
                            style: .continuous
                        )
                    )
            }
        }
        .frame(width: 16, height: 16)
        .saturation(presentation.shouldDesaturate ? 0 : 1)
        .opacity(presentation.shouldDesaturate ? 0.8 : 1)
    }
}

struct SplitGroupSegmentLabel<Icon: View>: View {
    let title: String
    let trailingPadding: CGFloat
    let textColor: Color
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 6) {
            icon()
            SumiTabTitleLabel(
                title: title,
                font: SidebarThemeTokens.Typography.rowTitleNSFont,
                textColor: textColor,
                trailingPadding: trailingPadding > 7 ? 2 : 0
            )
            .lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 7)
        .padding(.trailing, trailingPadding)
    }
}
