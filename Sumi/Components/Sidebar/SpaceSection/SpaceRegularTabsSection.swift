//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import AppKit
import SwiftUI

private enum RegularExternalDropGapPlacement: Equatable {
    case top
    case bottom
}

extension SpaceView {
    private var showsNewTabButtonInList: Bool {
        sumiSettings.showNewTabButtonInTabList
    }

    private var showsNewTabButtonAtTop: Bool {
        sumiSettings.tabListNewTabButtonPosition == .top
    }

    private var showsBottomNewTabButton: Bool {
        showsNewTabButtonInList && !showsNewTabButtonAtTop
    }

    private var tabs: [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return browserManager.tabManager.tabs(in: space)
    }

    private var newTabRow: some View {
        Button(action: openNewTabFloatingBar) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("New Tab")
                Spacer()
            }
            .foregroundStyle(tokens.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous)
                .fill(displayIsNewTabHovered ? tokens.sidebarRowHover : Color.clear)
                .padding(.horizontal, 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sidebarDDGHover($isNewTabHovered, isEnabled: isInteractive)
        .sidebarZenPressEffect(sourceID: newTabRowSourceID, isEnabled: isInteractive)
        .accessibilityIdentifier("space-new-tab-\(space.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isInteractive,
            sourceID: newTabRowSourceID,
            action: openNewTabFloatingBar
        )
    }

    private var newTabRowSourceID: String {
        "space-new-tab-\(space.id.uuidString)"
    }

    private var displayIsNewTabHovered: Bool {
        SidebarHoverChrome.displayHover(
            isNewTabHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func openNewTabFloatingBar() {
        guard isInteractive else { return }
        browserManager.showNewTabFloatingBar(in: windowState)
    }

    private var topNewTabButtonSection: some View {
        newTabRow
            .padding(.top, 4)
    }

    private var bottomNewTabButtonSection: some View {
        newTabRow
    }

    var regularTabsSection: some View {
        VStack(spacing: 0) {
            if regularExternalDropGapPlacement == .top {
                regularDropGap
            }

            SpaceSeparator(space: space, isHovering: $isSidebarHovered) {
                browserManager.tabManager.clearRegularTabs(for: space.id)
            }
            .environmentObject(browserManager)
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                if showsNewTabButtonInList && showsNewTabButtonAtTop {
                    topNewTabButtonSection
                }

                regularTabsListHitRegion

                if regularExternalDropGapPlacement == .bottom {
                    regularDropGap
                }

                if showsBottomNewTabButton {
                    bottomNewTabButtonSection
                }
            }
            .padding(.top, 8)

            regularTabsDragSpacer
        }
        .sidebarSectionGeometry(
            for: .spaceRegular,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: regularExternalDropGapPlacement
        )
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var regularTabsListHitRegion: some View {
        VStack(spacing: 0) {
            regularTabsListInner
        }
        .sidebarRegularListHitGeometry(
            for: space.id,
            itemCount: regularTabsRenderedRowCount,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var regularTabsRenderedRowCount: Int {
        regularProjectedItems(currentTabs: tabs).count
    }

    private var regularTabsListInner: some View {
        Group {
            if !tabs.isEmpty || regularTabsUsesProjectedDropLayout {
                regularTabsContent
            }
        }
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: regularProjectedItems(currentTabs: tabs)
        )
    }

    private var regularTabsContent: some View {
        VStack(spacing: 2) {
            let currentTabs = tabs
            let split = splitManager
            let windowId = windowState.id
            if !SidebarDragState.shared.isDragging,
               split.isSplit(for: windowId),
               let leftId = split.leftTabId(for: windowId), let rightId = split.rightTabId(for: windowId),
               let leftIdx = currentTabs.firstIndex(where: { $0.id == leftId }),
               let rightIdx = currentTabs.firstIndex(where: { $0.id == rightId }),
               leftIdx >= 0, rightIdx >= 0,
               leftIdx < currentTabs.count, rightIdx < currentTabs.count,
               leftIdx != rightIdx {
                splitTabsView(currentTabs: currentTabs, leftIdx: leftIdx, rightIdx: rightIdx)
            } else {
                regularTabsView(currentTabs: currentTabs)
            }
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var regularTabsDragSpacer: some View {
        Color.clear
            .frame(height: tabs.isEmpty ? 48 : 24)
    }

    private func splitTabsView(currentTabs: [Tab], leftIdx: Int, rightIdx: Int) -> some View {
        let firstIdx = min(leftIdx, rightIdx)
        let secondIdx = max(leftIdx, rightIdx)

        return ForEach(Array(currentTabs.enumerated()), id: \.element.id) { pair in
            let (idx, tab) = pair
            if idx == firstIdx {
                VStack(spacing: 2) {
                    let left = currentTabs[leftIdx]
                    let right = currentTabs[rightIdx]

                    SplitTabRow(
                        left: left,
                        right: right,
                        spaceId: space.id,
                        isAppKitInteractionEnabled: isInteractive,
                        contextMenuEntries: regularTabContextMenuEntries,
                        onActivate: onActivateTab,
                        onClose: onCloseTab
                    )
                    .environmentObject(browserManager)
                }
            } else if idx == secondIdx {
                EmptyView()
            } else {
                regularTabView(tab)
            }
        }
    }

    private func regularTabsView(currentTabs: [Tab]) -> some View {
        return LazyVStack(spacing: 2) {
            let tabById = Dictionary(uniqueKeysWithValues: currentTabs.map { ($0.id, $0) })
            ForEach(regularProjectedItems(currentTabs: currentTabs), id: \.self) { item in
                switch item {
                case .item(let tabId):
                    if let tab = tabById[tabId] {
                        VStack(spacing: 0) {
                            regularTabView(tab)
                        }
                    }
                case .placeholder:
                    regularDropGap
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !regularTabsUsesProjectedDropLayout {
                regularDropGuideOverlay(itemCount: currentTabs.count)
            }
        }
    }

    private func regularProjectedItems(currentTabs: [Tab]) -> [ProjectedItem<UUID>] {
        let sourceId = regularProjectedSourceId(in: currentTabs)
        let projectedInsertionIndex = regularProjectedInsertionIndex()
        return SidebarDropProjection.projectedItems(
            itemIDs: currentTabs.map(\.id),
            removesSourceID: sourceId,
            insertsPlaceholderAt: projectedInsertionIndex
        )
    }

    private var regularTabsUsesProjectedDropLayout: Bool {
        regularProjectedSourceId(in: tabs) != nil || regularProjectedInsertionIndex() != nil
    }

    private func regularProjectedSourceId(in currentTabs: [Tab]) -> UUID? {
        guard dragState.isDropProjectionActive,
              dragState.projectionDragScope?.sourceContainer == .spaceRegular(space.id),
              let projectionDragItemId = dragState.projectionDragItemId,
              currentTabs.contains(where: { $0.id == projectionDragItemId }) else {
            return nil
        }
        return projectionDragItemId
    }

    private func regularProjectedInsertionIndex() -> Int? {
        guard dragState.isDropProjectionActive,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.projectionHoveredSlot,
              hoveredSpaceId == space.id,
              regularExternalDropGapPlacement == nil else {
            return nil
        }
        if shouldSuppressRegularCommitGapForExternalShortcutSource {
            return nil
        }
        if let projectionDragItemId = dragState.projectionDragItemId,
           dragState.shouldHideCommittedCrossContainerPlaceholder(
                into: .spaceRegular(space.id),
                targetAlreadyContainsDraggedItem: tabs.contains { $0.id == projectionDragItemId }
           ) {
            return nil
        }
        return slot
    }

    private var shouldSuppressRegularCommitGapForExternalShortcutSource: Bool {
        guard dragState.isCompletingDrop,
              let sourceContainer = dragState.projectionDragScope?.sourceContainer,
              sourceContainer != .spaceRegular(space.id) else {
            return false
        }

        switch sourceContainer {
        case .essentials, .spacePinned, .folder:
            return true
        case .spaceRegular, .none:
            return false
        }
    }

    private var regularExternalDropGapPlacement: RegularExternalDropGapPlacement? {
        guard dragState.isDragging,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.hoveredSlot,
              hoveredSpaceId == space.id,
              let location = dragState.dragLocation,
              let listMetrics = dragState.regularListHitTargets[space.id] else {
            return nil
        }

        if slot == 0, location.y < listMetrics.frame.minY {
            return .top
        }

        if showsBottomNewTabButton,
           location.y > listMetrics.frame.maxY {
            return .bottom
        }

        return nil
    }

    private var regularDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .accessibilityHidden(true)
    }

    private func regularTabView(_ tab: Tab) -> some View {
        SpaceTab(
            tab: tab,
            dragSourceConfiguration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: tab.id,
                    title: tab.name,
                    urlString: tab.url.absoluteString
                ),
                sourceZone: .spaceRegular(space.id),
                previewKind: .row,
                previewIcon: tab.favicon,
                exclusionZones: regularTabExclusionZones(for: tab),
                onActivate: { handleUserTabActivation(tab) },
                isEnabled: !tab.isRenaming
                    && isInteractive
            ),
            isAppKitInteractionEnabled: isInteractive,
            action: { handleUserTabActivation(tab) },
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) },
            contextMenuEntries: regularTabContextMenuEntries(tab)
        )
        .opacity(
            dragState.isDragging && dragState.activeDragItemId == tab.id
                ? 0.001
                : 1
        )
        .id(tab.id)
        .sidebarZenRowLifecycleTransition(isEnabled: isInteractive)
        .accessibilityIdentifier("space-regular-tab-\(tab.id.uuidString)")
        .accessibilityValue(windowState.currentTabId == tab.id ? "selected" : "not selected")
    }

    private func regularTabContextMenuEntries(_ tab: Tab) -> [SidebarContextMenuEntry] {
        let folderChoices = browserManager.tabManager.folders(for: space.id).map { folder in
            SidebarContextMenuChoice(id: folder.id, title: folder.name)
        }
        let spaceChoices = browserManager.tabManager.spaces.map { targetSpace in
            SidebarContextMenuChoice(
                id: targetSpace.id,
                title: targetSpace.name,
                isSelected: targetSpace.id == tab.spaceId
            )
        }

        return makeRegularTabContextMenuEntries(
            folders: folderChoices,
            spaces: spaceChoices,
            showsAddToFavorites: !tab.isPinned && !tab.isSpacePinned,
            canMoveUp: !isFirstTab(tab),
            canMoveDown: !isLastTab(tab),
            showsCloseAllBelow: !tab.isPinned && !tab.isSpacePinned && tab.spaceId != nil,
            callbacks: .init(
                onAddToFolder: { folderId in
                    browserManager.tabManager.moveTabToFolder(tab: tab, folderId: folderId)
                },
                onAddToFavorites: {
                    browserManager.tabManager.pinTab(
                        tab,
                        context: .init(windowState: windowState, spaceId: space.id)
                    )
                },
                onCopyLink: { copyLink(tab.url) },
                onShare: {
                    presentSharePicker(
                        for: tab.url,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onRename: { tab.startRenaming() },
                onSplitRight: { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) },
                onSplitLeft: { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) },
                onDuplicate: { browserManager.duplicateTab(tab, in: windowState) },
                onMoveToSpace: { targetSpaceId in browserManager.tabManager.moveTab(tab.id, to: targetSpaceId) },
                onMoveUp: { onMoveTabUp(tab) },
                onMoveDown: { onMoveTabDown(tab) },
                onPinToSpace: { browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id) },
                onPinGlobally: { onPinTab(tab) },
                onCloseAllBelow: { browserManager.tabManager.closeAllTabsBelow(tab) },
                onClose: { onCloseTab(tab) }
            )
        )
    }

    private func regularDropGuideOverlay(itemCount: Int) -> some View {
        GeometryReader { geometry in
            if let localY = regularDropGuideLocalY(in: geometry, itemCount: itemCount) {
                dropLine()
                    .offset(y: localY - SidebarInsertionGuide.visualCenterY)
                    .transition(.opacity)
                    .animation(dropGuideAnimation, value: localY)
            }
        }
        .allowsHitTesting(false)
    }

    private func regularDropGuideLocalY(in geometry: GeometryProxy, itemCount: Int) -> CGFloat? {
        guard dragState.isDragging,
              case .spaceRegular(let hoveredSpaceId, let slot) = dragState.hoveredSlot,
              hoveredSpaceId == space.id,
              let metrics = dragState.regularListHitTargets[space.id],
              itemCount > 0 else {
            return nil
        }

        let safeSlot = max(0, min(slot, itemCount))
        let globalY: CGFloat
        if safeSlot == itemCount {
            globalY = metrics.frame.maxY
        } else {
            let rowSpacing = itemCount > 1
                ? max(0, (metrics.frame.height - (CGFloat(itemCount) * SidebarRowLayout.rowHeight)) / CGFloat(itemCount - 1))
                : 0
            globalY = metrics.frame.minY + CGFloat(safeSlot) * (SidebarRowLayout.rowHeight + rowSpacing)
        }

        return globalY - geometry.frame(in: .global).minY
    }

    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }

    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }

    private func handleUserTabActivation(_ tab: Tab) {
        browserManager.requestUserTabActivation(
            tab,
            in: windowState
        )
    }

    private func regularTabExclusionZones(for tab: Tab) -> [SidebarDragSourceExclusionZone] {
        var exclusions: [SidebarDragSourceExclusionZone] = [.trailingStrip(40)]
        if tab.audioState.showsTabAudioButton {
            exclusions.append(.fixedRect(SpaceTab.audioButtonHitFrame))
        }
        return exclusions
    }

    private func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource? = nil
    ) {
        if let source {
            browserManager.presentSharingServicePicker([url], source: source)
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
