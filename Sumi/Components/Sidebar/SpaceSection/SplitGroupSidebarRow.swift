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
    let currentTabId: UUID?
    let isAppKitInteractionEnabled: Bool
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let segmentAction: (SplitGroupSidebarItem) -> SplitGroupSidebarSegmentAction?
    var dragSource: (SplitGroupSidebarItem) -> SidebarDragSourceConfiguration? = { _ in nil }
    let contextMenuEntries: (Tab) -> [SidebarContextMenuEntry]
    let onActivateMember: (SplitMemberID) -> Void
    var onSegmentActionAnimationStart: (SplitMemberID) -> Void = { _ in }
    let onSegmentAction: (SplitMemberID) -> Void
    let onSegmentMiddleClick: (SplitMemberID) -> Void

    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @State var isRowHovered = false
    @State var displayedItems: [SplitGroupSidebarItem] = []
    @State var departingItemIds = Set<SplitMemberID>()
    @State var isCollapsingRow = false

    var body: some View {
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
                        isActive: isActive(item),
                        isDeparting: isDeparting(item),
                        segmentAction: segmentAction(item),
                        isAppKitInteractionEnabled: isAppKitInteractionEnabled && !isDeparting(item),
                        dragSourceConfiguration: dragSource(item),
                        contextMenuEntries: {
                            item.tab.map(splitContextMenuEntries) ?? []
                        },
                        onActivate: { activate(item) },
                        onSegmentAction: { performSegmentMutation(for: item, in: rowItems) },
                        onMiddleClick: { onSegmentMiddleClick(item.id) }
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
        .sidebarRowLifecycle(isCollapsed: isCollapsingRow)
        .padding(.horizontal, 2)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: rowBackground,
            cornerRadius: sumiSettings.resolvedCornerRadius(8),
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: isFocusedGroup
        )
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
        !isFocusedGroup && isAppKitInteractionEnabled
    }

    var isFocusedGroup: Bool {
        windowState.splitSelection?.groupID == group.id
    }

    func isActive(_ item: SplitGroupSidebarItem) -> Bool {
        if windowState.splitSelection?.groupID == group.id,
           windowState.splitSelection?.activeMemberID == item.id {
            return true
        }
        switch item.id {
        case .regularTab(let tabID):
            return currentTabId == tabID
        case .shortcutPin(let pinID):
            return windowState.currentShortcutPinId == pinID
        }
    }

    func splitContextMenuEntries(for tab: Tab) -> [SidebarContextMenuEntry] {
        var entries = contextMenuEntries(tab)
        let splitEntries: [SidebarContextMenuEntry] = [
            .submenu(
                title: "Split Layout",
                systemImage: "rectangle.split.2x2",
                children: [
                    .action(.init(title: "Grid", systemImage: "square.grid.2x2", onAction: {
                        splitLayout.setLayoutKind(.grid, in: windowState.id)
                    })),
                    .action(.init(title: "Vertical", systemImage: "rectangle.split.2x1", onAction: {
                        splitLayout.setLayoutKind(.vertical, in: windowState.id)
                    })),
                    .action(.init(title: "Horizontal", systemImage: "rectangle.split.1x2", onAction: {
                        splitLayout.setLayoutKind(.horizontal, in: windowState.id)
                    })),
                ]
            ),
            .submenu(
                title: "New Empty Split",
                systemImage: "plus.rectangle.on.rectangle",
                children: [
                    .action(.init(title: "Right", systemImage: "rectangle.righthalf.filled", onAction: {
                        emptySplitCreation.create(side: .right, in: windowState)
                    })),
                    .action(.init(title: "Left", systemImage: "rectangle.lefthalf.filled", onAction: {
                        emptySplitCreation.create(side: .left, in: windowState)
                    })),
                    .action(.init(title: "Top", systemImage: "rectangle.tophalf.filled", onAction: {
                        emptySplitCreation.create(side: .top, in: windowState)
                    })),
                    .action(.init(title: "Bottom", systemImage: "rectangle.bottomhalf.filled", onAction: {
                        emptySplitCreation.create(side: .bottom, in: windowState)
                    })),
                ]
            ),
            .action(.init(title: "Unsplit", systemImage: "rectangle", onAction: {
                performSplitSidebarMutation {
                    splitLayout.unsplit(in: windowState)
                }
            })),
        ]
        entries.append(.separator)
        entries.append(contentsOf: splitEntries)
        return entries
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
