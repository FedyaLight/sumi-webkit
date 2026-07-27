//
//  TabFolderBodyListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

private typealias FolderListItem = SidebarFolderListItem
private typealias FolderDisplayEntry = SidebarFolderDisplayEntry

/// Renders the folder's child list (nested folders, shortcuts, live items, splits, gaps).
struct TabFolderBodyListView: View {
    private static let folderContentLeadingPadding: CGFloat = 14

    let folder: TabFolder
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let elevatedFolderIds: Set<UUID>
    let isInteractive: Bool
    let nestingDepth: Int
    let contentProjection: SidebarFolderContentProjection
    let disclosurePresentation: SidebarDisclosurePresentation<SidebarFolderListItem>
    let projection: SidebarFolderViewProjection
    let reportsGeometry: Bool
    let reportsFolderChildGeometry: Bool
    let contextMenuActionOwner: TabFolderContextMenuActionOwner
    let mutationActions: TabFolderMutationActions
    let dragSnapshot: SidebarFolderDragSnapshot

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    var body: some View {
        let selectionSnapshot = sidebarSelection
        let childFoldersById = Dictionary(
            uniqueKeysWithValues: (inventory.childFoldersByParentID[folder.id] ?? []).map { ($0.id, $0) }
        )

        SidebarDisclosureTrackLayout(
            progress: disclosurePresentation.progress,
            sourceOrder: disclosurePresentation.sourceOrder,
            destinationOrder: disclosurePresentation.destinationOrder,
            sourceTopPadding: disclosurePresentation.sourceTopPadding,
            sourceBottomPadding: disclosurePresentation.sourceBottomPadding,
            destinationTopPadding: disclosurePresentation.destinationTopPadding,
            destinationBottomPadding: disclosurePresentation.destinationBottomPadding,
            itemSpacing: 0
        ) {
            ForEach(
                SidebarFolderDisplayProjection.displayEntries(
                    from: disclosurePresentation.items
                )
            ) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .folder(let folderId):
                        if let childFolder = childFoldersById[folderId],
                           let childPresentation = inventory.folderPresentation(id: folderId) {
                            TabFolderNestedFolderEntryView(
                                folder: childFolder,
                                presentation: childPresentation,
                                browserContext: browserContext,
                                space: space,
                                inventory: inventory,
                                selection: selection,
                                pinProjection: pinProjection,
                                pinCommands: pinCommands,
                                pinExecution: pinExecution,
                                folderCommands: folderCommands,
                                spaceLifecycle: spaceLifecycle,
                                elevatedFolderIDs: elevatedFolderIds,
                                isInteractive: isInteractive,
                                parentFolderID: folder.id,
                                containerIndex: entry.dropIndex,
                                nestingDepth: nestingDepth,
                                dragSnapshot: dragSnapshot
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: childFolder.id,
                                    index: entry.dropIndex,
                                    generation: dragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .shortcut(let pinId):
                        if let pin = projection.shortcutPin(with: pinId) {
                            shortcutEntry(
                                pin,
                                selectionSnapshot: selectionSnapshot
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: pin.id,
                                    index: entry.dropIndex,
                                    splitPairingMemberIDs: [.shortcutPin(pin.id)],
                                    generation: dragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .liveItem(let itemId):
                        if let item = projection.liveFolderItem(with: itemId) {
                            TabFolderLiveItemEntryView(
                                item: item,
                                folderID: folder.id,
                                isSelected: projection.currentTabURLString == item.urlString,
                                isInteractive: isInteractive,
                                actionOwner: contextMenuActionOwner
                            )
                        }
                    case .splitGroup(let groupId):
                        if let group = projection.splitGroup(with: groupId) {
                            TabFolderSplitGroupEntryView(
                                group: group,
                                items: projection.splitGroupItems(for: groupId),
                                space: space,
                                browserContext: browserContext,
                                isInteractive: isInteractive,
                                isDropHighlighted:
                                    dragSnapshot.isExistingSplitGroupTargeted(
                                        memberIDs: group.memberIDs
                                    )
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: group.id,
                                    index: entry.dropIndex,
                                    splitPairingMemberIDs: group.memberIDs,
                                    generation: dragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    }
                }
                .zIndex(
                    folderDisplayEntryZIndex(
                        entry,
                        selectionSnapshot: selectionSnapshot
                    )
                )
                .sidebarScrollTarget(scrollTargetID(for: entry.item))
            }
        }
        .clipped()
        .padding(.leading, Self.folderContentLeadingPadding)
    }

    private func scrollTargetID(
        for item: FolderListItem
    ) -> SidebarScrollTargetID {
        switch item {
        case .folder(let folderID):
            return .folder(folderID)
        case .shortcut(let pinID):
            return .launcher(pinID)
        case .liveItem(let itemID):
            return .liveFolderItem(folderID: folder.id, itemID: itemID)
        case .splitGroup(let groupID):
            return .splitGroup(groupID)
        }
    }

    private func folderDisplayEntryZIndex(
        _ entry: FolderDisplayEntry,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> Double {
        SidebarSelectionElevation.zIndex(
            isElevated: folderListItemIsElevated(
                entry.item,
                selectionSnapshot: selectionSnapshot
            )
        )
    }

    private func folderListItemIsElevated(
        _ item: FolderListItem,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> Bool {
        switch item {
        case .folder(let folderId):
            return elevatedFolderIds.contains(folderId)
        case .shortcut(let pinId):
            guard let pin = projection.shortcutPin(with: pinId) else {
                return false
            }
            return projection.isShortcutSelected(pin)
        case .liveItem(let itemId):
            guard let item = projection.liveFolderItem(with: itemId) else {
                return false
            }
            return projection.currentTabURLString == item.urlString
        case .splitGroup(let groupId):
            guard let group = projection.splitGroup(with: groupId) else {
                return false
            }
            return selection.isSplitGroupSelected(
                group,
                in: windowState,
                selection: selectionSnapshot
            )
        }
    }

    private func shortcutEntry(
        _ pin: ShortcutPin,
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> TabFolderShortcutEntryView {
        let presentationOwner = TabFolderShortcutPresentationOwner(
            pinProjection: pinProjection,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: selectionSnapshot
        )
        return TabFolderShortcutEntryView(
            pin: pin,
            liveTab: projection.liveTab(for: pin.id),
            faviconPartition: presentationOwner.faviconPartition(for: pin),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: presentationOwner.runtimeAffordance(for: pin),
            folderID: folder.id,
            isInteractive: isInteractive,
            opacity: dragSnapshot.childOpacity(itemID: pin.id),
            projectedSplitTarget: dragSnapshot.splitPairingTarget?
                .projectedTarget(for: .shortcutPin(pin.id)),
            contextMenuActionOwner: contextMenuActionOwner,
            mutationActions: mutationActions
        )
    }

}
