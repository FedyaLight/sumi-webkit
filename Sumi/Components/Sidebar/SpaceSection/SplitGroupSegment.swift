//
//  SplitGroupSegment.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SplitGroupSegment: View {
    let groupID: UUID
    let item: SplitGroupSidebarItem
    let spaceId: UUID
    let isDeparting: Bool
    let segmentWidth: CGFloat
    let trailingPadding: CGFloat
    let trailingActionExclusionWidth: CGFloat
    let memberAction: SplitGroupSidebarMemberAction?
    let isRowHovered: Bool
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let dragSourceConfiguration: SidebarDragSourceConfiguration?
    let dragPreviewSourceGeometry: SidebarDragPreviewSourceGeometry?
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onMemberAction: () -> Void
    let onMiddleClick: (() -> Void)?

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isSegmentHovered = false
    @State private var isActionHovered = false
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        hoverTrackedContent
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )
            .opacity(isDeparting ? 0 : 1)
            .task(id: item.tab?.url) {
                await item.tab?.fetchFaviconForVisiblePresentation()
            }
            .task(id: storedFaviconLoadKey) {
                await loadStoredFavicon()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .faviconCacheUpdated
                )
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
    private var hoverTrackedContent: some View {
        segmentContent.sidebarHover(
            $isSegmentHovered,
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var segmentContent: some View {
        ZStack(alignment: .trailing) {
            SplitGroupSegmentLabel(
                title: item.title,
                showsTitle: showsTitle,
                trailingPadding: trailingPadding,
                textColor: tokens.primaryText
            ) {
                icon
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .sidebarZenPressEffect(sourceID: rowSourceID, kind: .split)
            .sidebarAppKitContextMenu(
                isInteractionEnabled: (item.tab != nil || dragSourceConfiguration != nil) && isAppKitInteractionEnabled,
                dragSource: resolvedDragSourceConfiguration,
                primaryActionExclusionZones:
                    trailingActionExclusionZones,
                pageActivation: onActivate,
                onMiddleClick: onMiddleClick,
                sourceID: rowSourceID,
                entries: contextMenuEntries
            )

            if let memberAction {
                memberActionButton(memberAction)
                    .padding(.trailing, 4)
            }
        }
    }

    private func memberActionButton(
        _ action: SplitGroupSidebarMemberAction
    ) -> some View {
        Button(action: performMemberAction) {
            Image(systemName: action.systemImageName)
                .font(SidebarThemeTokens.Typography.trailingAction)
                .foregroundColor(tokens.primaryText)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(
                    displayIsActionHovering
                        ? tokens.fieldBackgroundHover : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsMemberAction && !freezesHoverState
            )
        )
        .opacity(showsMemberAction ? 1 : 0)
        .sidebarZenActionOpacity(showsMemberAction)
        .allowsHitTesting(showsMemberAction && !freezesHoverState)
        .accessibilityHidden(!showsMemberAction)
        .sidebarHover(
            $isActionHovered,
            isEnabled: showsMemberAction && isAppKitInteractionEnabled
        )
        .accessibilityIdentifier(
            "\(action.accessibilityPrefix)-\(item.stableIDDescription)"
        )
        .help(action.help)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsMemberAction && !freezesHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: performMemberAction
        )
    }

    private var showsMemberAction: Bool {
        memberAction != nil && (isRowHovered || isSegmentHovered)
    }

    private var showsTitle: Bool {
        SplitGroupSidebarVisualLayout.showsTitle(
            title: item.title,
            segmentWidth: segmentWidth,
            trailingPadding: trailingPadding
        )
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsActionHovering: Bool {
        isActionHovered
    }

    private func performMemberAction() {
        guard !isDeparting else { return }
        onMemberAction()
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
                trailingActionExclusionZones
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
            exclusionZones: trailingActionExclusionZones,
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var trailingActionExclusionZones: [SidebarDragSourceExclusionZone] {
        guard trailingActionExclusionWidth > 0 else { return [] }
        return [.trailingStrip(trailingActionExclusionWidth)]
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
        SplitGroupRowIconView(
            icon: presentation.rowIcon,
            foregroundColor: .primary,
            desaturates: presentation.shouldDesaturate
        )
    }
}

private extension SplitGroupMemberIconPresentation {
    var rowIcon: SplitGroupRowIcon {
        if let glyphText {
            return .emoji(glyphText)
        }
        if let systemImageName {
            return .system(systemImageName)
        }
        return .image(image)
    }
}
