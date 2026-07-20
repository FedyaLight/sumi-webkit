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
    private static let folderContentVerticalPadding: CGFloat = 4

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
    let projection: SidebarFolderViewProjection
    let reportsGeometry: Bool
    let reportsFolderChildGeometry: Bool
    let folderLayoutAnimation: Animation?
    let contextMenuActionOwner: TabFolderContextMenuActionOwner
    let mutationActions: TabFolderMutationActions
    let dragSnapshot: SidebarFolderDragSnapshot

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        let selectionSnapshot = sidebarSelection
        let childFoldersById = Dictionary(
            uniqueKeysWithValues: (inventory.childFoldersByParentID[folder.id] ?? []).map { ($0.id, $0) }
        )

        LazyVStack(spacing: 0) {
            ForEach(contentProjection.bodyDisplayEntries) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .folder(let folderId):
                        if let childFolder = childFoldersById[folderId] {
                            TabFolderNestedFolderEntryView(
                                folder: childFolder,
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
                                nestingDepth: nestingDepth
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
                                isInteractive: isInteractive
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: group.id,
                                    index: entry.dropIndex,
                                    generation: dragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .placeholder:
                        folderDropGap
                    }
                }
                .zIndex(
                    folderDisplayEntryZIndex(
                        entry,
                        selectionSnapshot: selectionSnapshot
                    )
                )
            }
        }
        .padding(.leading, Self.folderContentLeadingPadding)
        .padding(.vertical, Self.folderContentVerticalPadding)
        .background(alignment: .leading) {
            folderNestingGuide(isVisible: !contentProjection.bodyItems.isEmpty)
        }
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
    }

    @ViewBuilder
    private func folderNestingGuide(isVisible: Bool) -> some View {
        if isVisible {
            Rectangle()
                .fill(tokens.separator.opacity(0.55))
                .frame(width: 1)
                .padding(.vertical, 6)
                .offset(x: 6)
                .accessibilityHidden(true)
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
        case .placeholder:
            return false
        }
    }

    private var folderDropGap: some View {
        Color.clear
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .transition(.sidebarRowDropGap)
            .accessibilityHidden(true)
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
            contextMenuActionOwner: contextMenuActionOwner,
            mutationActions: mutationActions
        )
    }

}
