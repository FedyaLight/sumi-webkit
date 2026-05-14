//
//  SpaceRegularTabsSection.swift
//  Sumi
//

import AppKit
import SwiftUI

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
        Button(action: openNewTabCommandPalette) {
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
        .accessibilityIdentifier("space-new-tab-\(space.id.uuidString)")
        .sidebarAppKitPrimaryAction(isEnabled: isInteractive, action: openNewTabCommandPalette)
    }

    private var displayIsNewTabHovered: Bool {
        SidebarHoverChrome.displayHover(
            isNewTabHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func openNewTabCommandPalette() {
        guard isInteractive else { return }
        browserManager.showNewTabPalette(in: windowState)
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
    }

    private var regularTabsListHitRegion: some View {
        VStack(spacing: 0) {
            regularTabsListInner
        }
        .sidebarRegularListHitGeometry(
            for: space.id,
            itemCount: tabs.count,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    private var regularTabsListInner: some View {
        Group {
            if !tabs.isEmpty {
                regularTabsContent
            }
        }
        .animation(isInteractive ? .easeInOut(duration: 0.15) : nil, value: tabs.count)
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
            ForEach(Array(currentTabs.enumerated()), id: \.element.id) { index, tab in
                VStack(spacing: 0) {
                    regularTabView(tab)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            regularDropGuideOverlay(itemCount: currentTabs.count)
        }
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
        .transition(.move(edge: .top).combined(with: .opacity))
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
