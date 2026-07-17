//
//  SpacePinnedListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

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
    let pinnedItems: [SpacePinnedListItem]
    let dragSnapshot: SpacePinnedDragSnapshot
    let contentMutationAnimation: Animation?
    let actionOwner: SpacePinnedActionOwner
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession

    @Environment(BrowserWindowState.self) private var windowState

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

    private var elevatedFolderIDs: Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            selection: selection,
            windowState: windowState
        ).elevatedFolderIds
    }

    var body: some View {
        let foldersByID = Dictionary(uniqueKeysWithValues: topLevelFolders.map { ($0.id, $0) })
        let pinsByID = Dictionary(uniqueKeysWithValues: topLevelPins.map { ($0.id, $0) })

        LazyVStack(spacing: 0) {
            Color.clear
                .frame(height: SidebarInsertionGuide.visualCenterY)
                .allowsHitTesting(false)

            ForEach(projection.displayEntries) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
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
                            shortcutEntry(pin, topLevelIndex: entry.dropIndex)
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
                        shortcutRestoreGap(gapID)
                    }
                }
                .zIndex(displayEntryZIndex(entry))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            isInteractive && dragSnapshot.shouldAnimateDropLayout ? SidebarDropMotion.gap : nil,
            value: projection.projectedItems
        )
        .animation(contentMutationAnimation, value: pinnedItems)
        .animation(contentMutationAnimation, value: shortcutRestoreSession.gaps)
        .animation(contentMutationAnimation, value: shortcutRestoreSession.appearingGapIDs)
        .animation(contentMutationAnimation, value: projection.displayEntries.map(\.id))
        .padding(.bottom, 8)
    }

    private func shortcutEntry(
        _ pin: ShortcutPin,
        topLevelIndex: Int
    ) -> SpacePinnedShortcutEntryView {
        let placeholderGroup = regularSplitGroup(containing: pin.id)
        return SpacePinnedShortcutEntryView(
            pin: pin,
            placeholderGroup: placeholderGroup,
            placeholderIsSelected: placeholderGroup.map {
                isSplitPlaceholderSelected($0, pin: pin)
            } ?? false,
            liveTab: selection.liveTab(for: pin.id, in: windowState),
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: selection.runtimeAffordance(for: pin, in: windowState),
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

    private func shortcutRestoreGap(_ gapID: UUID) -> some View {
        let isAppearing = shortcutRestoreSession.appearingGapIDs.contains(gapID)
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreSession.gaps.first(where: { $0.id == gapID }),
               let pin = inventory.pin(id: gap.pinId) {
                shortcutEntry(pin, topLevelIndex: gap.index)
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

    private func displayEntryZIndex(_ entry: SpacePinnedDisplayEntry) -> Double {
        guard case .item(let item) = entry.item else { return 0 }
        return SidebarSelectionElevation.zIndex(isElevated: itemIsElevated(item))
    }

    private func itemIsElevated(_ item: SpacePinnedListItem) -> Bool {
        switch item {
        case .folder(let folderID):
            return elevatedFolderIDs.contains(folderID)
        case .shortcut(let pinID):
            guard let pin = topLevelPins.first(where: { $0.id == pinID }) else { return false }
            if let group = regularSplitGroup(containing: pin.id) {
                return isSplitPlaceholderSelected(group, pin: pin)
            }
            return selection.isShortcutSelected(pin, in: windowState)
        case .splitGroup(let groupID):
            guard let group = inventory.splitGroup(id: groupID) else { return false }
            return selection.isSplitGroupSelected(group, in: windowState)
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

    private func isSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        selection.isShortcutSelected(pin, in: windowState)
            || selection.isSplitMemberSelected(
                groupID: group.id,
                memberID: .shortcutPin(pin.id),
                in: windowState
            )
    }
}
