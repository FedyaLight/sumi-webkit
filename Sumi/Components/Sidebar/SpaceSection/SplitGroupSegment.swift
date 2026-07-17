//
//  SplitGroupSegment.swift
//  Sumi
//

import SwiftUI

struct SplitGroupSegment: View {
    let groupID: UUID
    let item: SplitGroupSidebarItem
    let spaceId: UUID
    let isActive: Bool
    let isDeparting: Bool
    let segmentAction: SplitGroupSidebarSegmentAction?
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let dragSourceConfiguration: SidebarDragSourceConfiguration?
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onSegmentAction: () -> Void
    let onMiddleClick: () -> Void

    @State private var isSegmentHoveredForActions = false
    @State private var isActionHovered = false
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                icon
                SumiTabTitleLabel(
                    title: item.title,
                    font: .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular),
                    textColor: tokens.primaryText,
                    trailingPadding: showsActionControls ? 2 : 0
                )
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 7)
            .padding(.trailing, showsActionControls ? 28 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .sidebarDDGHover(
                $isSegmentHoveredForActions,
                isEnabled: segmentAction != nil && isAppKitInteractionEnabled
            )
            .sidebarAppKitContextMenu(
                isInteractionEnabled: (item.tab != nil || dragSourceConfiguration != nil) && isAppKitInteractionEnabled,
                dragSource: resolvedDragSourceConfiguration,
                primaryAction: onActivate,
                onMiddleClick: onMiddleClick,
                sourceID: rowSourceID,
                entries: contextMenuEntries
            )

            if let segmentAction {
                segmentActionButton(segmentAction)
                    .padding(.trailing, 4)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(isDeparting ? 0 : 1)
        .task(id: item.tab?.url) {
            await item.tab?.fetchFaviconForVisiblePresentation()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let tab = item.tab {
            SidebarTabFaviconView(tab: tab, size: 16)
        } else if let pin = item.pin {
            pin.storedFaviconImage(
                partition: .regular(pin.executionProfileId ?? pin.profileId),
                imageReader: faviconImageReader
            )
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private var resolvedDragSourceConfiguration: SidebarDragSourceConfiguration? {
        if let dragSourceConfiguration {
            return dragSourceConfiguration
        }
        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitMember(
                item.id,
                groupID: groupID,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(spaceId),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: onActivate,
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var rowSourceID: String {
        "space-split-member-\(item.stableIDDescription)"
    }

    private var showsActionControls: Bool {
        guard segmentAction != nil else { return false }
        return SidebarHoverChrome.displayHover(
            isSegmentHoveredForActions,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var displayIsActionHovering: Bool {
        SidebarHoverChrome.displayHover(
            isActionHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func segmentActionButton(_ action: SplitGroupSidebarSegmentAction) -> some View {
        Button(action: performSegmentAction) {
            Image(systemName: action.systemImageName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tokens.primaryText)
                .frame(width: 20, height: 20)
                .background(displayIsActionHovering ? tokens.fieldBackgroundHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState
            )
        )
        .opacity(showsActionControls ? 1 : 0)
        .sidebarZenActionOpacity(showsActionControls)
        .allowsHitTesting(showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState)
        .sidebarDDGHover($isActionHovered, isEnabled: showsActionControls && isAppKitInteractionEnabled)
        .accessibilityIdentifier(
            "\(action.accessibilityPrefix)-\(item.stableIDDescription)"
        )
        .help(action.help)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: performSegmentAction
        )
    }

    private func performSegmentAction() {
        guard !isDeparting else { return }
        onSegmentAction()
    }

    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}
