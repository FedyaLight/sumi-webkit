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
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let groupEditor: SidebarSplitGroupEditorPresentationService
    var groupContextMenuActions: SplitGroupContextMenuActions = .empty
    let groupAction: SplitGroupSidebarAction?
    var dragSource: (SplitGroupSidebarItem) -> SidebarDragSourceConfiguration? = { _ in nil }
    let contextMenuEntries: (SplitGroupSidebarItem) -> [SidebarContextMenuEntry]
    let onActivateMember: (SplitMemberID) -> Void
    let onGroupAction: () -> Void

    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.chromeThemeTokens) var scopedChromeTokens
    @Environment(\.sidebarWindowSelectionSnapshot) var sidebarSelection
    @State var isRowHovered = false
    @State private var isActionHovered = false
    @State var displayedItems: [SplitGroupSidebarItem] = []
    @State var departingItemIds = Set<SplitMemberID>()

    var body: some View {
        rowContent
        .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
        .padding(.horizontal, 2)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: rowBackground,
            cornerRadius: sumiSettings.resolvedCornerRadius(
                SidebarRowLayout.defaultCornerRadius
            ),
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: isFocusedGroup
        )
        .overlay(alignment: .trailing) {
            trailingActionButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .sidebarDDGHover($isRowHovered, isEnabled: isRowHoverTrackingEnabled)
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
        GeometryReader { geometry in
            let rowItems = resolvedDisplayItems
            let activeCount = max(rowItems.filter { !isDeparting($0) }.count, 1)
            let separatorCount = max(activeCount - 1, 0)
            let segmentWidth = max(
                0,
                (geometry.size.width - CGFloat(separatorCount)) / CGFloat(activeCount)
            )

            HStack(spacing: 0) {
                ForEach(Array(rowItems.enumerated()), id: \.element.id) { index, item in
                    SplitGroupSegment(
                        groupID: group.id,
                        item: item,
                        spaceId: spaceId,
                        isDeparting: isDeparting(item),
                        trailingPadding: segmentTrailingPadding(
                            for: index,
                            in: rowItems
                        ),
                        reservesTrailingAction: isLastVisibleItem(
                            at: index,
                            in: rowItems
                        ) && groupAction != nil,
                        isAppKitInteractionEnabled: isAppKitInteractionEnabled && !isDeparting(item),
                        faviconImageReader: faviconImageReader,
                        dragSourceConfiguration: dragSource(item),
                        dragPreviewSourceGeometry: SidebarDragPreviewSourceGeometry(
                            size: geometry.size,
                            localOrigin: CGPoint(
                                x: segmentLeadingOffset(
                                    for: index,
                                    in: rowItems,
                                    segmentWidth: segmentWidth
                                ),
                                y: 0
                            )
                        ),
                        contextMenuEntries: {
                            groupContextMenuEntries
                        },
                        onActivate: { activate(item) },
                        onMiddleClick: groupAction == nil ? nil : onGroupAction
                    )
                    .frame(width: isDeparting(item) ? 0 : segmentWidth)
                    .clipped()

                    if shouldShowSeparator(after: index, in: rowItems) {
                        Rectangle()
                            .fill(tokens.separator.opacity(0.7))
                            .frame(width: 1, height: 22)
                            .padding(.vertical, 6)
                    }
                }
            }
            .animation(
                shouldAnimateProjectedLayout ? SidebarDropMotion.contentLayout : nil,
                value: displayedItems.map(\.id)
            )
            .animation(
                shouldAnimateProjectedLayout ? SidebarDropMotion.contentLayout : nil,
                value: departingItemIds.map(\.sidebarStableDescription).sorted()
            )
        }
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
                .padding(.trailing, titleTrailingPadding)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { activate(activationItem) }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            surfaceKind: .row,
            dragSource: dragSource(activationItem),
            primaryAction: { activate(activationItem) },
            onMiddleClick: groupAction == nil ? nil : onGroupAction,
            sourceID: "split-group-custom-icon-\(group.id.uuidString)",
            entries: { groupContextMenuEntries }
        )
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
        return SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    var isRowHoverTrackingEnabled: Bool {
        isAppKitInteractionEnabled
    }

    var isFocusedGroup: Bool {
        sidebarSelection.splitSelection?.groupID == group.id
    }

    private var showsGroupAction: Bool {
        guard let groupAction else { return false }
        return SidebarHoverChrome.showsTrailingAction(
            isHovered: SidebarHoverChrome.displayHover(
                isRowHovered,
                freezesHoverState:
                    windowState.sidebarInteractionState.freezesSidebarHoverState
            ),
            isSelected: groupAction.showsWhenSelected && isFocusedGroup
        )
    }

    private var titleTrailingPadding: CGFloat {
        SidebarHoverChrome.trailingPadding(
            showsTrailingAction: showsGroupAction
        )
    }

    private func segmentTrailingPadding(
        for index: Int,
        in rowItems: [SplitGroupSidebarItem]
    ) -> CGFloat {
        isLastVisibleItem(at: index, in: rowItems) && showsGroupAction
            ? SidebarRowLayout.trailingActionPadding : 7
    }

    private func isLastVisibleItem(
        at index: Int,
        in rowItems: [SplitGroupSidebarItem]
    ) -> Bool {
        rowItems[(index + 1)...].contains { !isDeparting($0) } == false
    }

    private func segmentLeadingOffset(
        for index: Int,
        in rowItems: [SplitGroupSidebarItem],
        segmentWidth: CGFloat
    ) -> CGFloat {
        let precedingVisibleCount = rowItems[..<index].count {
            !isDeparting($0)
        }
        return CGFloat(precedingVisibleCount) * (segmentWidth + 1)
    }

    @ViewBuilder
    private var trailingActionButton: some View {
        if let groupAction {
            Button(action: onGroupAction) {
                Image(systemName: groupAction.systemImageName)
                    .font(SidebarThemeTokens.Typography.trailingAction)
                    .foregroundColor(tokens.primaryText)
                    .frame(
                        width: SidebarRowLayout.trailingActionSize,
                        height: SidebarRowLayout.trailingActionSize
                    )
                    .background(
                        displayIsActionHovering
                            ? actionBackground : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(
                SidebarZenActionButtonStyle(
                    isEnabled: showsGroupAction && !freezesHoverState
                )
            )
            .opacity(showsGroupAction ? 1 : 0)
            .sidebarZenActionOpacity(showsGroupAction)
            .allowsHitTesting(showsGroupAction && !freezesHoverState)
            .accessibilityHidden(!showsGroupAction)
            .sidebarDDGHover(
                $isActionHovered,
                isEnabled: showsGroupAction && isAppKitInteractionEnabled
            )
            .accessibilityIdentifier(
                "\(groupAction.accessibilityPrefix)-\(group.id.uuidString)"
            )
            .help(groupAction.help)
            .sidebarAppKitPrimaryAction(
                isEnabled: showsGroupAction && !freezesHoverState,
                isInteractionEnabled: isAppKitInteractionEnabled,
                action: onGroupAction
            )
        }
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsActionHovering: Bool {
        SidebarHoverChrome.displayHover(
            isActionHovered,
            freezesHoverState: freezesHoverState
        )
    }

    private var actionBackground: Color {
        isFocusedGroup ? tokens.fieldBackgroundHover : tokens.fieldBackground
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
