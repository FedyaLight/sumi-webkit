//
//  TabFolderBodyListView.swift
//  Sumi
//

import SwiftUI
import SumiDomain

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
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let shortcutPins: [ShortcutPin]
    let childFolders: [TabFolder]
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
    @Binding var shortcutRestoreGaps: [ShortcutRestoreGap]
    @Binding var shortcutRestoreAppearingGapIds: Set<UUID>
    let elevatedFolderIds: Set<UUID>
    let renderMode: SpaceViewRenderMode
    let nestingDepth: Int
    let contentProjection: SidebarFolderContentProjection
    let projection: SidebarFolderViewProjection
    let reportsGeometry: Bool
    let reportsFolderChildGeometry: Bool
    let folderLayoutAnimation: Animation?
    let contextMenuActionOwner: TabFolderContextMenuActionOwner
    let mutationActions: TabFolderMutationActions
    let onPrepareShortcutRestoreGap: (UUID, SplitMemberID) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (
        UUID,
        SplitMemberID,
        @escaping () -> Void
    ) -> Void
    let onActivateShortcutPin: (ShortcutPin) -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @EnvironmentObject private var dragState: SidebarDragState

    private var folderDragSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(dragState: dragState)
    }

    private var isInteractive: Bool {
        renderMode.isInteractive
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        let childFoldersById = Dictionary(uniqueKeysWithValues: childFolders.map { ($0.id, $0) })
        let shortcutPinsById = Dictionary(uniqueKeysWithValues: shortcutPins.map { ($0.id, $0) })

        LazyVStack(spacing: 0) {
            ForEach(contentProjection.bodyDisplayEntries) { entry in
                VStack(spacing: 0) {
                    switch entry.item {
                    case .folder(let folderId):
                        if let childFolder = childFoldersById[folderId] {
                            nestedFolderView(childFolder, containerIndex: entry.dropIndex)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: childFolder.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .shortcut(let pinId):
                        if let pin = shortcutPinsById[pinId] {
                            folderShortcutView(pin)
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: pin.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .liveItem(let itemId):
                        if let item = projection.liveFolderItem(with: itemId) {
                            liveFolderItemView(item)
                        }
                    case .splitGroup(let groupId):
                        if let group = projection.splitGroup(with: groupId) {
                            shortcutHostedSplitGroupView(
                                group,
                                items: projection.splitGroupItems(for: groupId)
                            )
                                .sidebarFolderChildDropGeometry(
                                    spaceId: space.id,
                                    folderId: folder.id,
                                    childId: group.id,
                                    index: entry.dropIndex,
                                    generation: folderDragSnapshot.geometryGeneration,
                                    isActive: isInteractive && reportsGeometry && reportsFolderChildGeometry
                                )
                        }
                    case .restoreGap(let gapId):
                        shortcutRestoreGap(gapId)
                    case .placeholder:
                        folderDropGap
                    }
                }
                .zIndex(folderDisplayEntryZIndex(entry))
            }
        }
        .padding(.leading, Self.folderContentLeadingPadding)
        .padding(.vertical, Self.folderContentVerticalPadding)
        .background(alignment: .leading) {
            folderNestingGuide(isVisible: !contentProjection.bodyItems.isEmpty)
        }
        .animation(folderLayoutAnimation, value: contentProjection.bodyItems)
    }

    private func nestedFolderView(_ childFolder: TabFolder, containerIndex: Int) -> some View {
        TabFolderView(
            folder: childFolder,
            browserContext: browserContext,
            space: space,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            spaceLifecycle: spaceLifecycle,
            shortcutPins: folderPinsByFolderId[childFolder.id] ?? [],
            childFolders: childFoldersByParentId[childFolder.id] ?? [],
            childFoldersByParentId: childFoldersByParentId,
            folderPinsByFolderId: folderPinsByFolderId,
            shortcutRestoreGaps: $shortcutRestoreGaps,
            shortcutRestoreAppearingGapIds: $shortcutRestoreAppearingGapIds,
            elevatedFolderIds: elevatedFolderIds,
            renderMode: renderMode,
            parentFolderId: folder.id,
            containerIndex: containerIndex,
            nestingDepth: nestingDepth + 1,
            onUngroup: {
                mutationActions.ungroupNestedFolder(childFolder)
            },
            onDelete: {
                mutationActions.deleteNestedFolder(childFolder)
            },
            onPrepareShortcutRestoreGap: onPrepareShortcutRestoreGap,
            onPerformShortcutRestoreWithPreparedGap: onPerformShortcutRestoreWithPreparedGap
        )
        .environment(windowState)
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

    private func folderDisplayEntryZIndex(_ entry: FolderDisplayEntry) -> Double {
        SidebarSelectionElevation.zIndex(
            isElevated: folderListItemIsElevated(entry.item)
        )
    }

    private func folderListItemIsElevated(_ item: FolderListItem) -> Bool {
        switch item {
        case .folder(let folderId):
            return elevatedFolderIds.contains(folderId)
        case .shortcut(let pinId):
            guard let pin = shortcutPins.first(where: { $0.id == pinId }) else {
                return false
            }
            if let placeholderGroup = projection.regularPlaceholderGroup(for: pin.id) {
                return isFolderSplitPlaceholderSelected(placeholderGroup, pin: pin)
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
            return selection.isSplitGroupSelected(group, in: windowState)
        case .restoreGap, .placeholder:
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

    private func shortcutRestoreGap(_ gapId: UUID) -> some View {
        let isAppearing = shortcutRestoreAppearingGapIds.contains(gapId)
        return ZStack(alignment: .topLeading) {
            if let gap = shortcutRestoreGaps.first(where: { $0.id == gapId }),
               let pin = projection.shortcutPin(with: gap.pinId) {
                folderShortcutView(pin)
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

    @ViewBuilder
    private func shortcutHostedSplitGroupView(
        _ group: SplitGroup,
        items: [SplitGroupSidebarItem]
    ) -> some View {
        if !items.isEmpty {
            ShortcutHostedSplitGroupRow(
                group: group,
                items: items,
                spaceId: space.id,
                splitLayout: browserContext.splitLayout,
                emptySplitCreation: browserContext.emptySplitCreation,
                isAppKitInteractionEnabled: isInteractive,
                accessibilityID: "folder-shortcut-host-split-row-\(group.id.uuidString)",
                onActivateMember: { memberID in
                    browserContext.commands.focusSplitGroup(
                        group.id,
                        memberID,
                        windowState.id
                    )
                },
                onRestoreShortcutMember: { memberID in
                    browserContext.commands.restoreShortcutSplitMember(
                        group.id,
                        memberID,
                        windowState.id
                    )
                },
                onCloseMember: { memberID in
                    browserContext.commands.closeSplitMember(
                        group.id,
                        memberID,
                        windowState.id
                    )
                },
                onPrepareShortcutRestoreGap: { memberID in
                    onPrepareShortcutRestoreGap(group.id, memberID)
                },
                onPerformShortcutRestoreWithPreparedGap: { memberID, update in
                    onPerformShortcutRestoreWithPreparedGap(
                        group.id,
                        memberID,
                        update
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func folderShortcutView(_ pin: ShortcutPin) -> some View {
        if let placeholderGroup = projection.regularPlaceholderGroup(for: pin.id) {
            ShortcutSplitPlaceholderRow(
                pin: pin,
                isSelected: isFolderSplitPlaceholderSelected(placeholderGroup, pin: pin),
                accessibilityID: "folder-split-placeholder-\(pin.id.uuidString)",
                isAppKitInteractionEnabled: isInteractive,
                action: {
                    browserContext.commands.focusSplitGroup(
                        placeholderGroup.id,
                        .shortcutPin(pin.id),
                        windowState.id
                    )
                }
            )
            .opacity(
                folderDragSnapshot.childOpacity(itemID: pin.id)
            )
        } else {
            ShortcutSidebarRow(
                pin: pin,
                liveTab: projection.liveTab(for: pin.id),
                faviconPartition: TabFolderShortcutPresentationOwner(
                    pinProjection: pinProjection,
                    selection: selection,
                    windowState: windowState
                ).faviconPartition(for: pin),
                runtimeAffordance: TabFolderShortcutPresentationOwner(
                    pinProjection: pinProjection,
                    selection: selection,
                    windowState: windowState
                ).runtimeAffordance(for: pin),
                accessibilityID: "folder-shortcut-\(pin.id.uuidString)",
                contextMenuEntries: {
                    contextMenuActionOwner.folderShortcutContextMenuEntries(pin)
                },
                action: { onActivateShortcutPin(pin) },
                dragSourceZone: .folder(folder.id),
                dragHasTrailingActionExclusion: true,
                dragIsEnabled: isInteractive,
                onResetToLaunchURL: { contextMenuActionOwner.resetShortcutPin(pin) },
                onUnload: { contextMenuActionOwner.unloadShortcutPin(pin) },
                onRemove: { contextMenuActionOwner.removeShortcutPin(pin) }
            )
            .opacity(
                folderDragSnapshot.childOpacity(itemID: pin.id)
            )
        }
    }

    private func liveFolderItemView(_ item: SumiLiveFolderItem) -> some View {
        SumiLiveFolderItemRow(
            item: item,
            isSelected: projection.currentTabURLString == item.urlString,
            accessibilityID: "live-folder-item-\(folder.id.uuidString)-\(item.id)",
            contextMenuEntries: {
                contextMenuActionOwner.liveFolderItemContextMenuEntries(item)
            },
            action: {
                browserContext.liveFolderManager.open(item: item, in: windowState)
            },
            onDismiss: {
                browserContext.liveFolderManager.dismiss(item: item)
            }
        )
        .environment(windowState)
    }

    private func isFolderSplitPlaceholderSelected(_ group: SplitGroup, pin: ShortcutPin) -> Bool {
        selection.isShortcutSelected(pin, in: windowState)
            || selection.isSplitMemberSelected(
                groupID: group.id,
                memberID: .shortcutPin(pin.id),
                in: windowState
            )
    }

}
