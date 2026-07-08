//
//  SpacePinnedSection.swift
//  Sumi
//

import SwiftUI

extension SpaceView {
    private var launcherProjection: SpaceLauncherProjectionSnapshot? {
        guard windowState.isIncognito == false else { return nil }
        return browserContext.tabManager.spaceLauncherProjectionOwner.projection(for: space.id, in: windowState.id)
    }

    private var topLevelPinnedPins: [ShortcutPin] {
        if windowState.isIncognito {
            return []
        }
        return launcherProjection?.topLevelPins ?? []
    }

    private var folders: [TabFolder] {
        if windowState.isIncognito {
            return []
        }
        return launcherProjection?.topLevelFolders ?? []
    }

    private var hasSpacePinnedContent: Bool {
        !spacePinnedItems.isEmpty
            || shortcutRestoreGaps.contains { $0.container == .spacePinned(space.id) }
    }

    private var showsEmptyPinnedDropPlaceholder: Bool {
        !hasSpacePinnedContent
            && isInteractive
            && isHoveringThisSpacePinnedWhileEmpty
    }

    private var isHoveringThisSpacePinnedWhileEmpty: Bool {
        guard case .spacePinned(let sid, _) = dragState.hoveredSlot else { return false }
        return sid == space.id
    }

    private var dropGuideEdgeAllowance: CGFloat {
        SidebarInsertionGuide.visualCenterY
    }

    private var spacePinnedItems: [SpacePinnedListItem] {
        guard !windowState.isIncognito else { return [] }
        return browserContext.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id)
    }

    private var spacePinnedDisplayModel: SpacePinnedDisplayModel {
        let hoveredSpaceId: UUID?
        let hoveredSlot: Int?
        if case .spacePinned(let slotSpaceId, let slot) = dragState.projectionHoveredSlot {
            hoveredSpaceId = slotSpaceId
            hoveredSlot = slot
        } else {
            hoveredSpaceId = nil
            hoveredSlot = nil
        }

        return SpacePinnedDisplayModel(
            spaceId: space.id,
            items: spacePinnedItems,
            restoreGaps: shortcutRestoreGaps,
            dragProjection: .init(
                isDropProjectionActive: dragState.isDropProjectionActive,
                sourceContainer: dragState.projectionDragScope?.sourceContainer,
                dragItemId: dragState.projectionDragItemId,
                hoveredSpaceId: hoveredSpaceId,
                hoveredSlot: hoveredSlot,
                folderDropIntent: dragState.projectionFolderDropIntent,
                shouldHideCommittedCrossContainerPlaceholder: { targetAlreadyContainsDraggedItem in
                    dragState.shouldHideCommittedCrossContainerPlaceholder(
                        into: .spacePinned(space.id),
                        targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
                    )
                }
            )
        )
    }

    private var projectedSpacePinnedItems: [ProjectedItem<SpacePinnedListItem>] {
        spacePinnedDisplayModel.projectedItems
    }

    private var projectedSpacePinnedDisplayEntries: [SpacePinnedDisplayEntry] {
        spacePinnedDisplayModel.displayEntries
    }

    private var renderedSpacePinnedItems: [SpacePinnedRenderedItem] {
        spacePinnedDisplayModel.renderedItems
    }

    private var spacePinnedActionOwner: SpacePinnedActionOwner {
        SpacePinnedActionOwner(
            space: space,
            browserContext: browserContext,
            windowState: windowState,
            themeContext: themeContext,
            contentMutationAnimation: sidebarContentMutationAnimation
        )
    }

    var pinnedTabsSection: some View {
        Group {
            if hasSpacePinnedContent {
                pinnedTabsList
                    .transition(
                        isInteractive
                            ? .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.3)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.2))
                            )
                            : .identity
                    )
            } else {
                pinnedRevealStrip
            }
        }
        .animation(isInteractive ? .easeInOut(duration: 0.25) : nil, value: hasSpacePinnedContent)
        .animation(isInteractive ? .easeInOut(duration: 0.18) : nil, value: showsEmptyPinnedDropPlaceholder)
        .animation(sidebarContentMutationAnimation, value: spacePinnedItems)
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .sidebarSectionGeometry(
            for: .spacePinned,
            spaceId: space.id,
            generation: dragState.sidebarGeometryGeneration,
            isEnabled: isInteractive
        )
    }

    @ViewBuilder
    private func shortcutHostedSplitGroupView(_ group: SplitGroup, topLevelPinnedIndex: Int) -> some View {
        let items = SplitGroupSidebarModel.items(for: group, tabManager: browserContext.tabManager)
        if !items.isEmpty {
            ShortcutHostedSplitGroupRow(
                group: group,
                items: items,
                spaceId: space.id,
                tabManager: browserContext.tabManager,
                isAppKitInteractionEnabled: isInteractive,
                accessibilityID: "shortcut-host-split-row-\(group.id.uuidString)",
                onActivateTab: { tab in
                    browserContext.commands.requestUserTabActivation(tab, windowState)
                },
                onActivateGroup: { group in
                    browserContext.commands.focusSplitGroup(group, windowState)
                },
                onRestoreShortcutSplitMember: { item, group in
                    browserContext.commands.restoreShortcutSplitMember(item.id, group, windowState)
                },
                onCloseTab: { tab in
                    browserContext.commands.closeTab(tab, windowState)
                },
                onPrepareShortcutRestoreGap: { item, group in
                    prepareShortcutRestoreGap(for: item, in: group)
                },
                onPerformShortcutRestoreWithPreparedGap: { item, group, update in
                    performShortcutRestoreWithPreparedGap(for: item, in: group, update: update)
                }
            )
            .environmentObject(splitManager)
            .sidebarTopLevelPinnedItemGeometry(
                itemId: group.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
            .sidebarRowListItemTransition(isEnabled: isInteractive)
        }
    }

    private var pinnedTabsList: some View {
        let allItems = projectedSpacePinnedDisplayEntries
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let pinsById = Dictionary(uniqueKeysWithValues: topLevelPinnedPins.map { ($0.id, $0) })

        return LazyVStack(spacing: 0) {
            Color.clear
                .frame(height: dropGuideEdgeAllowance)
                .allowsHitTesting(false)

            ForEach(allItems) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .item(.folder(let folderId)):
                        if let folder = foldersById[folderId] {
                            mixedFolderView(folder, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .item(.shortcut(let pinId)):
                        if let pin = pinsById[pinId] {
                            pinnedShortcutView(pin, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .item(.splitGroup(let groupId)):
                        if let group = browserContext.tabManager.splitGroupCollectionStateOwner.group(with: groupId) {
                            shortcutHostedSplitGroupView(group, topLevelPinnedIndex: entry.dropIndex)
                        }
                    case .dragPlaceholder:
                        pinnedDropGap
                    case .restoreGap(let gapId):
                        shortcutRestoreGap(gapId)
                    }
                }
                .zIndex(spacePinnedDisplayEntryZIndex(entry))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            isInteractive && dragState.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projectedSpacePinnedItems
        )
        .animation(sidebarContentMutationAnimation, value: spacePinnedItems)
        .animation(sidebarContentMutationAnimation, value: shortcutRestoreGaps)
        .animation(sidebarContentMutationAnimation, value: shortcutRestoreAppearingGapIds)
        .animation(
            sidebarContentMutationAnimation,
            value: projectedSpacePinnedDisplayEntries.map(\.id)
        )
        .padding(.bottom, 8) // Add padding to act as drag tail for spacePinned
    }

    private func spacePinnedDisplayEntryZIndex(_ entry: SpacePinnedDisplayEntry) -> Double {
        guard case .item(let item) = entry.item else {
            return 0
        }
        return SidebarSelectionElevation.zIndex(isElevated: spacePinnedItemIsElevated(item))
    }

    private func spacePinnedItemIsElevated(_ item: SpacePinnedListItem) -> Bool {
        switch item {
        case .folder(let folderId):
            return folderContainsElevatedSelection(folderId)
        case .shortcut(let pinId):
            guard let pin = topLevelPinnedPins.first(where: { $0.id == pinId }) else {
                return false
            }
            if let placeholderGroup = browserContext.tabManager.splitGroupStructureOwner.regularHostedSplitGroup(containingPinId: pin.id) {
                return isPinnedSplitPlaceholderSelected(placeholderGroup, pin: pin)
            }
            return shortcutPinIsElevated(pin)
        case .splitGroup(let groupId):
            guard let group = browserContext.tabManager.splitGroupCollectionStateOwner.group(with: groupId) else {
                return false
            }
            return splitGroupIsElevated(group)
        }
    }

    private func shortcutPinIsElevated(_ pin: ShortcutPin) -> Bool {
        browserContext.tabManager.shortcutPresentationOwner.shortcutRuntimeAffordanceState(for: pin, in: windowState).isSelected
    }

    private func splitGroupIsElevated(_ group: SplitGroup) -> Bool {
        SidebarSelectionElevation.splitGroupContainsCurrentTab(
            group,
            currentTabId: windowState.currentTabId
        )
    }

    private func folderContainsElevatedSelection(_ folderId: UUID) -> Bool {
        elevatedFolderIds.contains(folderId)
    }

    private var pinnedDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
    }

    private func shortcutRestoreGap(_ gapId: UUID) -> some View {
        let isAppearing = shortcutRestoreAppearingGapIds.contains(gapId)
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }),
               let pin = browserContext.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: gap.pinId) {
                pinnedShortcutView(pin, topLevelPinnedIndex: gap.index)
                    .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
            }
        }
        .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowStagedInsertion(isRevealing: isAppearing)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pinnedRevealStrip: some View {
        VStack(spacing: 0) {
            if showsEmptyPinnedDropPlaceholder {
                Color.clear
                    .frame(height: SidebarRowLayout.rowHeight)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(
            height: showsEmptyPinnedDropPlaceholder ? SidebarRowLayout.rowHeight : 6,
            alignment: .top
        )
    }

    private func mixedFolderView(_ folder: TabFolder, topLevelPinnedIndex: Int) -> some View {
        TabFolderView(
            folder: folder,
            browserContext: browserContext,
            space: space,
            shortcutPins: launcherProjection?.folderPins[folder.id] ?? [],
            childFolders: launcherProjection?.childFolders[folder.id] ?? [],
            childFoldersByParentId: launcherProjection?.childFolders ?? [:],
            folderPinsByFolderId: launcherProjection?.folderPins ?? [:],
            shortcutRestoreGaps: $shortcutRestoreGaps,
            shortcutRestoreAppearingGapIds: $shortcutRestoreAppearingGapIds,
            elevatedFolderIds: elevatedFolderIds,
            renderMode: renderMode,
            parentFolderId: nil,
            containerIndex: topLevelPinnedIndex,
            nestingDepth: 0,
            onUngroup: { spacePinnedActionOwner.ungroupFolder(folder) },
            onDelete: { spacePinnedActionOwner.deleteFolder(folder) },
            onPrepareShortcutRestoreGap: { item, group in
                prepareShortcutRestoreGap(for: item, in: group)
            },
            onPerformShortcutRestoreWithPreparedGap: { item, group, update in
                performShortcutRestoreWithPreparedGap(for: item, in: group, update: update)
            }
        )
        .environment(windowState)
        .sidebarTopLevelPinnedItemGeometry(
            itemId: folder.id,
            spaceId: space.id,
            topLevelIndex: topLevelPinnedIndex,
            generation: dragState.sidebarGeometryGeneration,
            isActive: isInteractive
        )
        .sidebarZenCompositeLifecycleTransition(isEnabled: isInteractive)
    }

    @ViewBuilder
    private func pinnedShortcutView(_ pin: ShortcutPin, topLevelPinnedIndex: Int) -> some View {
        if let placeholderGroup = browserContext.tabManager.splitGroupStructureOwner.regularHostedSplitGroup(containingPinId: pin.id) {
            ShortcutSplitPlaceholderRow(
                pin: pin,
                isSelected: isPinnedSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "space-pinned-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isInteractive,
                action: {
                    browserContext.commands.focusSplitGroup(placeholderGroup, windowState)
                }
            )
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .sidebarTopLevelPinnedItemGeometry(
                itemId: pin.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
            .sidebarRowListItemTransition(isEnabled: isInteractive)
        } else {
            let activeTab = activeShortcutTab(for: pin)
            ShortcutSidebarRow(
                pin: pin,
                liveTab: activeTab,
                faviconPartition: browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
                    for: pin,
                    currentSpaceId: windowState.currentSpaceId
                ),
                runtimeAffordance: browserContext.tabManager.shortcutPresentationOwner.shortcutRuntimeAffordanceState(
                    for: pin,
                    in: windowState
                ),
                accessibilityID: "space-pinned-shortcut-\(pin.id.uuidString)",
                contextMenuEntries: {
                    spacePinnedActionOwner.pinnedShortcutContextMenuEntries(pin)
                },
                action: { activateShortcutPin(pin) },
                dragSourceZone: .spacePinned(space.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onResetToLaunchURL: { spacePinnedActionOwner.resetShortcutPin(pin) },
                onUnload: { spacePinnedActionOwner.unloadShortcutPin(pin) },
                onRemove: { spacePinnedActionOwner.removeShortcutPin(pin) }
            )
            .opacity(
                dragState.isDragging && dragState.activeDragItemId == pin.id
                    ? 0.001
                    : 1
            )
            .sidebarTopLevelPinnedItemGeometry(
                itemId: pin.id,
                spaceId: space.id,
                topLevelIndex: topLevelPinnedIndex,
                generation: dragState.sidebarGeometryGeneration,
                isActive: isInteractive
            )
            .sidebarRowListItemTransition(isEnabled: isInteractive)
        }
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserContext.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id)
    }

    private func isPinnedSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        if windowState.currentShortcutPinId == pin.id {
            return true
        }
        guard let currentTabId = windowState.currentTabId else {
            return false
        }
        return group.contains(currentTabId)
            || group.member(forPinId: pin.id)?.tabId == currentTabId
    }

    private func activateShortcutPin(_ pin: ShortcutPin) {
        let tab = browserContext.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        browserContext.commands.requestUserTabActivation(
            tab,
            windowState
        )
    }

}
