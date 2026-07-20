//
//  SpaceRegularSplitGroupEntryView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Behavior boundary for one split group hosted by the regular-tab list.
/// The list owns row ordering and animation state; this leaf resolves only the
/// group's segments and routes their exact actions.
struct SpaceRegularSplitGroupEntryView: View {
    let group: SplitGroup
    let space: Space
    let tabByID: [UUID: Tab]
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let contentMutationAnimation: Animation?
    let tabActionOwner: SpaceRegularTabActionOwner
    let onCloseRegularTab: (Tab) -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var splitResolver: RegularSplitSegmentResolver {
        RegularSplitSegmentResolver(space: space, isInteractive: isInteractive)
    }

    private var items: [SplitGroupSidebarItem] {
        splitResolver.splitGroupItems(
            for: group,
            tabByID: tabByID,
            regularTab: { regularTabCatalog.tab(for: $0) },
            shortcutLiveTab: { selection.liveTab(for: $0, in: windowState) },
            shortcutPin: { regularTabTargets.shortcutPin(by: $0) }
        )
    }

    var body: some View {
        SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: space.id,
            isAppKitInteractionEnabled: isInteractive,
            faviconImageReader: browserContext.faviconImageReader,
            splitLayout: browserContext.splitLayout,
            emptySplitCreation: browserContext.emptySplitCreation,
            groupEditor: browserContext.splitGroupEditor,
            groupContextMenuActions: browserContext.splitGroupLifecycle
                .contextMenuActions(for: group, in: windowState),
            groupAction: SplitGroupSidebarModel.rowAction(
                for: group,
                items: items
            ),
            dragSource: splitSegmentDragSource,
            contextMenuEntries: splitContextMenuEntries,
            onActivateMember: activateMember,
            onGroupAction: closeGroup
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: SidebarSelectionElevation.splitGroupIsSelected(
                    group,
                    selectedGroupID: sidebarSelection.splitSelection?.groupID
                )
            )
        )
    }

    private func splitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        splitResolver.dragSource(
            for: item,
            in: group,
            faviconImageReader: browserContext.faviconImageReader,
            shortcutPin: { regularTabTargets.shortcutPin(by: $0) },
            splitPresentation: splitDragPresentation,
            isGroupSelected:
                sidebarSelection.splitSelection?.groupID == group.id,
            onActivateMember: {
                browserContext.splitFocusCommands.focusGroup(
                    group.id,
                    item.id,
                    windowState.id
                )
            }
        )
    }

    private var splitDragPresentation: SidebarSplitDragPresentation {
        SidebarSplitDragPresentation(
            members: zip(items, iconPresentations).map { item, icon in
                SidebarSplitDragPresentation.Member(
                    icon: icon.image,
                    glyphText: icon.glyphText,
                    systemImageName: icon.systemImageName,
                    accentColor: accentColor(for: item),
                    title: item.title
                )
            }
        )
    }

    private var iconPresentations: [SplitGroupMemberIconPresentation] {
        items.map { item in
            SplitGroupMemberIconResolver.resolve(
                item: item,
                loadedStoredFavicon: nil,
                imageReader: browserContext.faviconImageReader
            )
        }
    }

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private func accentColor(for item: SplitGroupSidebarItem) -> Color {
        PinnedTileAccentResolver.resolve(
            launchURL: item.tab?.url ?? item.pin?.launchURL,
            partition: item.pin.map {
                .regular($0.executionProfileId ?? $0.profileId)
            },
            glyphText: item.pin?.glyphText,
            chromeTemplateSystemImageName:
                item.pin?.chromeTemplateSystemImageName,
            tokens: tokens
        )
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private func splitContextMenuEntries(
        _ item: SplitGroupSidebarItem
    ) -> [SidebarContextMenuEntry] {
        guard let tab = item.tab else { return [] }
        return tabActionOwner.contextMenuEntries(
            for: tab,
            close: { onCloseRegularTab(tab) }
        )
    }

    private func activateMember(_ memberID: SplitMemberID) {
        browserContext.splitFocusCommands.focusGroup(
            group.id,
            memberID,
            windowState.id
        )
    }

    private func closeGroup() {
        browserContext.splitGroupLifecycle.closeRegular(
            group,
            in: windowState
        )
    }
}
