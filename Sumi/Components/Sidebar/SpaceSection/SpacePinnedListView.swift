//
//  SpacePinnedListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

private enum SpacePinnedContentRenderedItem {
    case pinned(SpacePinnedRenderedItem)
    case nestedSticky(UUID)
}

private struct SpacePinnedContentDisplayEntry: Identifiable {
    let item: SpacePinnedContentRenderedItem
    let dropIndex: Int
    let id: String
}

/// Renders and reorders the top-level saved folders, shortcuts, and split groups.
struct SpacePinnedListView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let isCollapsed: Bool
    let pinnedItems: [SpacePinnedListItem]
    let stickyItemIDs: [UUID]
    let dragSnapshot: SpacePinnedDragSnapshot
    let contentMutationAnimation: Animation?
    let actionOwner: SpacePinnedActionOwner
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var topLevelPins: [ShortcutPin] {
        windowState.isIncognito ? [] : inventory.topLevelPins
    }

    private var topLevelFolders: [TabFolder] {
        windowState.isIncognito ? [] : inventory.topLevelFolders
    }

    private var projection: SpacePinnedListProjection {
        SpacePinnedListProjection(
            spaceId: space.id,
            items: pinnedItems,
            restoreGaps: shortcutRestoreSession.gaps,
            dragProjection: dragSnapshot.projection
        )
    }

    private var contentDisplayEntries: [SpacePinnedContentDisplayEntry] {
        guard isCollapsed else {
            return projection.displayEntries.map { entry in
                SpacePinnedContentDisplayEntry(
                    item: .pinned(entry.item),
                    dropIndex: entry.dropIndex,
                    id: entry.id
                )
            }
        }

        return stickyItemIDs.compactMap { itemID in
            if let index = pinnedItems.firstIndex(where: { $0.id == itemID }) {
                return SpacePinnedContentDisplayEntry(
                    item: .pinned(.item(pinnedItems[index])),
                    dropIndex: index,
                    id: "item-\(itemID.uuidString)"
                )
            }

            guard inventory.pin(id: itemID) != nil
                    || inventory.splitGroup(id: itemID) != nil else {
                return nil
            }
            return SpacePinnedContentDisplayEntry(
                item: .nestedSticky(itemID),
                dropIndex: 0,
                id: "item-\(itemID.uuidString)"
            )
        }
    }

    private var showsCollapsedEmptyTarget: Bool {
        isCollapsed && stickyItemIDs.isEmpty
    }

    private var leadingSpacerHeight: CGFloat {
        guard showsCollapsedEmptyTarget else {
            return SidebarInsertionGuide.visualCenterY
        }
        return isInteractive && dragSnapshot.isHoveringEmptySection
            ? SidebarRowLayout.rowHeight
            : 6
    }

    private var bottomPadding: CGFloat {
        showsCollapsedEmptyTarget ? 0 : 8
    }

    private func elevatedFolderIDs(
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: selectionSnapshot
        ).elevatedFolderIds
    }

    var body: some View {
        let selectionSnapshot = sidebarSelection
        let elevatedFolderIDs = elevatedFolderIDs(
            selectionSnapshot: selectionSnapshot
        )
        let foldersByID = Dictionary(uniqueKeysWithValues: topLevelFolders.map { ($0.id, $0) })
        let pinsByID = Dictionary(uniqueKeysWithValues: topLevelPins.map { ($0.id, $0) })

        LazyVStack(spacing: 0) {
            Color.clear
                .frame(height: leadingSpacerHeight)
                .allowsHitTesting(false)

            ForEach(contentDisplayEntries) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .pinned(let item):
                        switch item {
                        case .item(.folder(let folderID)):
                            if let folder = foldersByID[folderID] {
                                SpacePinnedFolderEntryView(
                                    folder: folder,
                                    space: space,
                                    inventory: inventory,
                                    selection: selection,
                                    pinProjection: pinProjection,
                                    pinCommands: pinCommands,
                                    pinExecution: pinExecution,
                                    folderCommands: folderCommands,
                                    spaceLifecycle: spaceLifecycle,
                                    browserContext: browserContext,
                                    shortcutRestoreSession: $shortcutRestoreSession,
                                    elevatedFolderIDs: elevatedFolderIDs,
                                    topLevelIndex: entry.dropIndex,
                                    geometryGeneration: dragSnapshot.geometryGeneration,
                                    isInteractive: isInteractive
                                )
                            }
                        case .item(.shortcut(let pinID)):
                            if let pin = pinsByID[pinID] {
                                shortcutEntry(
                                    pin,
                                    topLevelIndex: entry.dropIndex,
                                    selectionSnapshot: selectionSnapshot
                                )
                            }
                        case .item(.splitGroup(let groupID)):
                            if let group = inventory.splitGroup(id: groupID) {
                                SpacePinnedSplitGroupEntryView(
                                    group: group,
                                    items: SplitGroupSidebarModel.items(
                                        for: group,
                                        inventory: inventory,
                                        selection: selection,
                                        windowState: windowState
                                    ),
                                    space: space,
                                    inventory: inventory,
                                    browserContext: browserContext,
                                    isInteractive: isInteractive,
                                    topLevelIndex: entry.dropIndex,
                                    geometryGeneration: dragSnapshot.geometryGeneration,
                                    contentMutationAnimation: contentMutationAnimation,
                                    shortcutRestoreSession: $shortcutRestoreSession
                                )
                            }
                        case .dragPlaceholder:
                            dropGap
                        case .restoreGap(let gapID):
                            shortcutRestoreGap(
                                gapID,
                                selectionSnapshot: selectionSnapshot
                            )
                        }
                    case .nestedSticky(let itemID):
                        SpaceNestedPinnedStickyEntryView(
                            space: space,
                            inventory: inventory,
                            selection: selection,
                            pinProjection: pinProjection,
                            pinCommands: pinCommands,
                            pinExecution: pinExecution,
                            folderCommands: folderCommands,
                            spaceLifecycle: spaceLifecycle,
                            browserContext: browserContext,
                            isInteractive: isInteractive,
                            itemID: itemID,
                            dragSnapshot: dragSnapshot,
                            contentMutationAnimation: contentMutationAnimation,
                            shortcutRestoreSession: $shortcutRestoreSession
                        )
                    }
                }
                .zIndex(
                    displayEntryZIndex(
                        entry,
                        selectionSnapshot: selectionSnapshot,
                        elevatedFolderIDs: elevatedFolderIDs
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, bottomPadding)
        .animation(
            isInteractive && dragSnapshot.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projection.projectedItems
        )
        .animation(contentMutationAnimation, value: pinnedItems)
        .animation(contentMutationAnimation, value: shortcutRestoreSession.gaps)
        .animation(contentMutationAnimation, value: shortcutRestoreSession.appearingGapIDs)
        .animation(contentMutationAnimation, value: contentDisplayEntries.map(\.id))
        .animation(contentMutationAnimation, value: isCollapsed)
    }

    private func shortcutEntry(
        _ pin: ShortcutPin,
        topLevelIndex: Int,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> SpacePinnedShortcutEntryView {
        let placeholderGroup = regularSplitGroup(containing: pin.id)
        return SpacePinnedShortcutEntryView(
            pin: pin,
            placeholderGroup: placeholderGroup,
            placeholderIsSelected: placeholderGroup.map {
                isSplitPlaceholderSelected(
                    $0,
                    pin: pin,
                    selectionSnapshot: selectionSnapshot
                )
            } ?? false,
            liveTab: selection.liveTab(for: pin.id, in: windowState),
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: selection.runtimeAffordance(
                for: pin,
                in: windowState,
                selection: selectionSnapshot
            ),
            spaceID: space.id,
            isInteractive: isInteractive,
            opacity: itemOpacity(pin.id),
            topLevelIndex: topLevelIndex,
            geometryGeneration: dragSnapshot.geometryGeneration,
            actionOwner: actionOwner
        )
    }

    private var dropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
    }

    private func shortcutRestoreGap(
        _ gapID: UUID,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> some View {
        let isAppearing = shortcutRestoreSession.appearingGapIDs.contains(gapID)
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreSession.gaps.first(where: { $0.id == gapID }),
               let pin = inventory.pin(id: gap.pinId) {
                shortcutEntry(
                    pin,
                    topLevelIndex: gap.index,
                    selectionSnapshot: selectionSnapshot
                )
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

    private func displayEntryZIndex(
        _ entry: SpacePinnedContentDisplayEntry,
        selectionSnapshot: SidebarWindowSelectionSnapshot,
        elevatedFolderIDs: Set<UUID>
    ) -> Double {
        guard case .pinned(.item(let item)) = entry.item else { return 0 }
        return SidebarSelectionElevation.zIndex(
            isElevated: itemIsElevated(
                item,
                selectionSnapshot: selectionSnapshot,
                elevatedFolderIDs: elevatedFolderIDs
            )
        )
    }

    private func itemIsElevated(
        _ item: SpacePinnedListItem,
        selectionSnapshot: SidebarWindowSelectionSnapshot,
        elevatedFolderIDs: Set<UUID>
    ) -> Bool {
        switch item {
        case .folder(let folderID):
            return elevatedFolderIDs.contains(folderID)
        case .shortcut(let pinID):
            guard let pin = topLevelPins.first(where: { $0.id == pinID }) else { return false }
            if let group = regularSplitGroup(containing: pin.id) {
                return isSplitPlaceholderSelected(
                    group,
                    pin: pin,
                    selectionSnapshot: selectionSnapshot
                )
            }
            return selection.isShortcutSelected(
                pin,
                in: windowState,
                selection: selectionSnapshot
            )
        case .splitGroup(let groupID):
            guard let group = inventory.splitGroup(id: groupID) else { return false }
            return selection.isSplitGroupSelected(
                group,
                in: windowState,
                selection: selectionSnapshot
            )
        }
    }

    private func itemOpacity(_ itemID: UUID) -> Double {
        dragSnapshot.isDragging && dragSnapshot.activeDragItemID == itemID ? 0.001 : 1
    }

    private func regularSplitGroup(containing pinID: UUID) -> SplitGroup? {
        guard let group = inventory.splitGroup(containing: .shortcutPin(pinID)),
              !group.container.isShortcutSidebar else {
            return nil
        }
        return group
    }

    private func isSplitPlaceholderSelected(
        _ group: SplitGroup,
        pin: ShortcutPin,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> Bool {
        selection.isShortcutSelected(
            pin,
            in: windowState,
            selection: selectionSnapshot
        )
            || selection.isSplitMemberSelected(
                groupID: group.id,
                memberID: .shortcutPin(pin.id),
                in: windowState,
                selection: selectionSnapshot
            )
    }
}
