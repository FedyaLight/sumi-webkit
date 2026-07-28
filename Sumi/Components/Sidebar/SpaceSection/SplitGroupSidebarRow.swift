//
//  SplitGroupSidebarRow.swift
//  Sumi
//

import SumiDomain
import SwiftUI

struct SplitGroupSidebarRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    var isDropHighlighted = false
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let groupEditor: SidebarSplitGroupEditorPresentationService
    var groupContextMenuActions: SplitGroupContextMenuActions = .empty
    var groupAction: SplitGroupSidebarAction? = nil
    var memberAction: (SplitGroupSidebarItem) -> SplitGroupSidebarMemberAction? = { _ in nil }
    var dragSource: (SplitGroupSidebarItem) -> SidebarDragSourceConfiguration? = { _ in nil }
    let contextMenuEntries: (SplitGroupSidebarItem) -> [SidebarContextMenuEntry]
    let onActivateMember: (SplitMemberID) -> Void
    var onMemberAction: (SplitGroupSidebarItem) -> Void = { _ in }
    var onGroupAction: (SplitGroupSidebarAction) -> Void = { _ in }

    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.chromeThemeTokens) var scopedChromeTokens
    @Environment(\.sidebarWindowSelectionSnapshot) var sidebarSelection
    @State var isRowHovered = false
    @State var displayedItems: [SplitGroupSidebarItem] = []
    @State var departingItemIds = Set<SplitMemberID>()

    var body: some View {
        rowContent
        .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
        .padding(.horizontal, SplitGroupSidebarVisualLayout.outerRowInset)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background {
            if isDropHighlighted {
                Rectangle()
                    .fill(tokens.sidebarRowHover)
            }
        }
        .sidebarRowSurface(
            background: rowBackground,
            cornerRadius: sumiSettings.resolvedCornerRadius(
                SidebarRowLayout.defaultCornerRadius
            ),
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: isFocusedGroup
        )
        .sidebarSelectedItemVisibility(
            .splitGroup(group.id),
            isSelected: isFocusedGroup,
            isEnabled: isAppKitInteractionEnabled
        )
        .overlay(alignment: .trailing) {
            trailingActionButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .sidebarHover($isRowHovered, isEnabled: isRowHoverTrackingEnabled)
        .accessibilityIdentifier("space-split-group-\(group.id.uuidString)")
        .onAppear {
            if displayedItems.isEmpty {
                displayedItems = items
            }
        }
        .onChange(of: items.map(\.id)) { _, _ in
            reconcileDisplayedItems(with: items)
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if let iconAsset = group.iconAsset,
           let activationItem = customIconActivationItem {
            customIconRow(iconAsset, activationItem: activationItem)
        } else {
            segmentedRow
        }
    }

    private var segmentedRow: some View {
        let rowItems = resolvedDisplayItems
        return SplitGroupSegmentedRow(
            slots: rowItems,
            material: .settled(isSelected: isFocusedGroup),
            tokens: tokens,
            departingIDs: departingItemIds
        ) { index, item, metrics in
            let itemAction = memberAction(item)
            SplitGroupSegment(
                groupID: group.id,
                item: item,
                spaceId: spaceId,
                isDeparting: isDeparting(item),
                segmentWidth: metrics.width,
                trailingPadding: segmentTrailingPadding(
                    for: index,
                    in: rowItems
                ),
                trailingActionExclusionWidth: trailingActionExclusionWidth(
                    hasMemberAction: itemAction != nil,
                    isLastVisibleItem: isLastVisibleItem(
                        at: index,
                        in: rowItems
                    )
                ),
                memberAction: itemAction,
                isRowHovered: isRowHovered,
                isAppKitInteractionEnabled:
                    isAppKitInteractionEnabled && !isDeparting(item),
                faviconImageReader: faviconImageReader,
                dragSourceConfiguration: dragSource(item),
                dragPreviewSourceGeometry: SidebarDragPreviewSourceGeometry(
                    size: metrics.rowSize,
                    localOrigin: CGPoint(
                        x: metrics.leadingOffset,
                        y: 0
                    )
                ),
                contextMenuEntries: {
                    groupContextMenuEntries
                },
                onActivate: { activate(item) },
                onMemberAction: { onMemberAction(item) },
                onMiddleClick: middleClickAction(for: item)
            )
        }
        .animation(
            shouldAnimateProjectedLayout
                ? SidebarDropMotion.contentLayout : nil,
            value: displayedItems.map(\.id)
        )
        .animation(
            shouldAnimateProjectedLayout
                ? SidebarDropMotion.contentLayout : nil,
            value: departingItemIds.map(\.sidebarStableDescription).sorted()
        )
    }

    private func customIconRow(
        _ iconAsset: String,
        activationItem: SplitGroupSidebarItem
    ) -> some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            Group {
                if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                    Text(iconAsset)
                        .font(SidebarThemeTokens.Typography.launcherEmoji(
                            size: SidebarRowLayout.faviconSize
                        ))
                } else {
                    Image(systemName:
                        SumiPersistentGlyph.resolvedLauncherSystemImageName(
                            iconAsset
                        )
                    )
                    .symbolRenderingMode(.monochrome)
                }
            }
            .frame(
                width: SidebarRowLayout.faviconSize,
                height: SidebarRowLayout.faviconSize
            )
            .saturation(isSavedGroupUnloaded ? 0 : 1)
            .opacity(isSavedGroupUnloaded ? 0.8 : 1)

            Text(groupDisplayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, reservedTrailingWidth)
        }
        .padding(
            .leading,
            SplitGroupSidebarVisualLayout.customIconLeadingInset
        )
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { activate(activationItem) }
        .sidebarZenPressEffect(sourceID: customIconSourceID, kind: .split)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            surfaceKind: .row,
            dragSource: dragSource(activationItem),
            primaryActionExclusionZones:
                groupActionExclusionZones,
            pageActivation: { activate(activationItem) },
            onMiddleClick: middleClickGroupAction,
            sourceID: customIconSourceID,
            entries: { groupContextMenuEntries }
        )
    }

    private var customIconSourceID: String {
        "split-group-custom-icon-\(group.id.uuidString)"
    }

    private var customIconActivationItem: SplitGroupSidebarItem? {
        if let activeID = sidebarSelection.splitSelection?.activeMemberID,
           let active = items.first(where: { $0.id == activeID }) {
            return active
        }
        return items.first
    }

    private var groupDisplayTitle: String {
        SplitGroupSidebarModel.displayTitle(for: group)
    }

    private var isSavedGroupUnloaded: Bool {
        switch group.container {
        case .regularTabs:
            return false
        case .essentialSidebar, .shortcutSidebar:
            return items.contains { $0.tab != nil } == false
        }
    }

    func activate(_ item: SplitGroupSidebarItem) {
        onActivateMember(item.id)
    }

    var rowBackground: Color {
        if isFocusedGroup {
            return tokens.sidebarRowActive
        }
        if showsRowHoverBackground {
            return tokens.sidebarRowHover
        }
        return Color.clear
    }

    var drawsRowSurface: Bool {
        isFocusedGroup || showsRowHoverBackground
    }

    var showsRowHoverBackground: Bool {
        guard !isFocusedGroup else { return false }
        return isRowHovered
    }

    var isRowHoverTrackingEnabled: Bool {
        isAppKitInteractionEnabled
    }

    var isFocusedGroup: Bool {
        sidebarSelection.splitSelection?.groupID == group.id
    }

    private var showsGroupAction: Bool {
        guard groupAction != nil else { return false }
        return SidebarHoverChrome.showsTrailingAction(
            isHovered: isRowHovered,
            isSelected: false
        )
    }

    private var reservedTrailingWidth: CGFloat {
        showsGroupAction ? SidebarRowLayout.trailingActionPadding : 0
    }

    private func segmentTrailingPadding(
        for index: Int,
        in rowItems: [SplitGroupSidebarItem]
    ) -> CGFloat {
        SplitGroupSidebarVisualLayout.trailingPadding(
            hasMemberAction: memberAction(rowItems[index]) != nil,
            showsMemberAction: isRowHovered,
            isLastVisibleItem: isLastVisibleItem(
                at: index,
                in: rowItems
            ),
            groupActionTrailingPadding:
                showsGroupAction
                    ? SidebarRowLayout.trailingActionPadding
                    : 0
        )
    }

    private func middleClickAction(
        for item: SplitGroupSidebarItem
    ) -> (() -> Void)? {
        if memberAction(item) != nil {
            return { onMemberAction(item) }
        }
        return middleClickGroupAction
    }

    private func isLastVisibleItem(
        at index: Int,
        in rowItems: [SplitGroupSidebarItem]
    ) -> Bool {
        rowItems[(index + 1)...].contains { !isDeparting($0) } == false
    }

    @ViewBuilder
    private var trailingActionButton: some View {
        if let groupAction {
            SplitGroupTrailingActionButton(
                action: groupAction,
                groupID: group.id,
                showsAction: showsGroupAction,
                isInteractionEnabled: isAppKitInteractionEnabled,
                freezesHoverState: freezesHoverState,
                textColor: tokens.primaryText,
                hoverBackground: actionBackground,
                perform: { onGroupAction(groupAction) }
            )
        }
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var actionBackground: Color {
        isFocusedGroup ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    private var groupActionExclusionWidth: CGFloat {
        guard groupAction != nil else { return 0 }
        return SidebarRowLayout.trailingActionPadding
            + SidebarRowLayout.trailingInset
    }

    private var groupActionExclusionZones: [SidebarDragSourceExclusionZone] {
        guard groupActionExclusionWidth > 0 else { return [] }
        return [.trailingStrip(groupActionExclusionWidth)]
    }

    private var middleClickGroupAction: (() -> Void)? {
        guard groupAction == .unload else { return nil }
        return { onGroupAction(.unload) }
    }

    private func trailingActionExclusionWidth(
        hasMemberAction: Bool,
        isLastVisibleItem: Bool
    ) -> CGFloat {
        if hasMemberAction {
            return SidebarRowLayout.trailingActionSize
                + SidebarRowLayout.trailingActionGap * 2
        }
        return isLastVisibleItem ? groupActionExclusionWidth : 0
    }

    var groupContextMenuEntries: [SidebarContextMenuEntry] {
        SplitGroupContextMenuFactory.entries(
            for: group,
            members: items.compactMap { item in
                guard let url = item.tab?.url ?? item.pin?.launchURL else {
                    return nil
                }
                return SplitGroupContextMenuMember(
                    id: item.id,
                    title: item.title,
                    url: url,
                    additionalEntries: contextMenuEntries(item)
                )
            },
            splitLayout: splitLayout,
            emptySplitCreation: emptySplitCreation,
            windowState: windowState,
            actions: resolvedGroupContextMenuActions
        )
    }

    private var resolvedGroupContextMenuActions: SplitGroupContextMenuActions {
        var actions = groupContextMenuActions
        actions.edit = {
            groupEditor.show(
                group,
                in: windowState,
                themeContext: themeContext
            )
        }
        actions.duplicate = {
            groupEditor.duplicate(group, in: windowState)
        }
        actions.moveTo = groupEditor.moveMenuEntries(
            for: group,
            in: windowState
        )
        if group.memberIDs.count < SplitGroup.maximumMembers,
           let activationItem = customIconActivationItem ?? items.first {
            actions.addTab = {
                onActivateMember(activationItem.id)
                _ = emptySplitCreation.create(
                    side: .right,
                    in: windowState,
                    reason: .splitTabPicker
                )
            }
        }
        if let delete = actions.delete {
            actions.delete = {
                groupEditor.confirmDelete(
                    group,
                    in: windowState,
                    themeContext: themeContext,
                    onDelete: delete
                )
            }
        }
        return actions
    }
}

private struct SplitGroupTrailingActionButton: View {
    let action: SplitGroupSidebarAction
    let groupID: UUID
    let showsAction: Bool
    let isInteractionEnabled: Bool
    let freezesHoverState: Bool
    let textColor: Color
    let hoverBackground: Color
    let perform: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: action.systemImageName)
                .font(SidebarThemeTokens.Typography.trailingAction)
                .foregroundColor(textColor)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(isHovered ? hoverBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsAction && !freezesHoverState
            )
        )
        .opacity(showsAction ? 1 : 0)
        .sidebarZenActionOpacity(showsAction)
        .allowsHitTesting(showsAction && !freezesHoverState)
        .accessibilityHidden(!showsAction)
        .sidebarHover(
            $isHovered,
            isEnabled: showsAction && isInteractionEnabled
        )
        .accessibilityIdentifier(
            "\(action.accessibilityPrefix)-\(groupID.uuidString)"
        )
        .help(action.help)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsAction && !freezesHoverState,
            isInteractionEnabled: isInteractionEnabled,
            action: perform
        )
    }
}

private extension SplitMemberID {
    var sidebarStableDescription: String {
        switch self {
        case .regularTab(let tabID):
            return "regular-tab-\(tabID.uuidString)"
        case .shortcutPin(let pinID):
            return "shortcut-pin-\(pinID.uuidString)"
        }
    }
}
