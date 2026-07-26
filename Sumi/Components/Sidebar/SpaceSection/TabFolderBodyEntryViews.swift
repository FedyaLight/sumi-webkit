//
//  TabFolderBodyEntryViews.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// One recursive child folder; the parent list owns only slot geometry.
struct TabFolderNestedFolderEntryView: View {
    let folder: TabFolder
    let presentation: SidebarFolderPresentationCell
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let elevatedFolderIDs: Set<UUID>
    let isInteractive: Bool
    let parentFolderID: UUID
    let containerIndex: Int
    let nestingDepth: Int
    let dragSnapshot: SidebarFolderDragSnapshot

    var body: some View {
        TabFolderView(
            folder: folder,
            presentation: presentation,
            browserContext: browserContext,
            space: space,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            elevatedFolderIds: elevatedFolderIDs,
            isInteractive: isInteractive,
            parentFolderId: parentFolderID,
            containerIndex: containerIndex,
            nestingDepth: nestingDepth + 1,
            dragSnapshot: dragSnapshot
        )
    }
}

/// One saved shortcut with presentation resolved before entering the leaf.
struct TabFolderShortcutEntryView: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let folderID: UUID
    let isInteractive: Bool
    let opacity: Double
    let projectedSplitTarget: SidebarSplitPairingTarget?
    let contextMenuActionOwner: TabFolderContextMenuActionOwner
    let mutationActions: TabFolderMutationActions

    var body: some View {
        ShortcutSidebarRow(
            pin: pin,
            liveTab: liveTab,
            faviconPartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            runtimeAffordance: runtimeAffordance,
            projectedSplitTarget: projectedSplitTarget,
            accessibilityID: "folder-shortcut-\(pin.id.uuidString)",
            contextMenuEntries: {
                contextMenuActionOwner.folderShortcutContextMenuEntries(pin)
            },
            action: { mutationActions.activateShortcutPin(pin) },
            dragSourceZone: .folder(folderID),
            dragHasTrailingActionExclusion: true,
            dragIsEnabled: isInteractive,
            onResetToLaunchURL: { contextMenuActionOwner.resetShortcutPin(pin) },
            onUnload: { contextMenuActionOwner.unloadShortcutPin(pin) },
            onRemove: { contextMenuActionOwner.removeShortcutPin(pin) }
        )
        .opacity(opacity)
    }
}

/// One live-folder result. Live-folder behavior stays on its existing owner.
struct TabFolderLiveItemEntryView: View {
    let item: SumiLiveFolderItem
    let folderID: UUID
    let isSelected: Bool
    let isInteractive: Bool
    let actionOwner: TabFolderContextMenuActionOwner

    var body: some View {
        SumiLiveFolderItemRow(
            item: item,
            isSelected: isSelected,
            accessibilityID: "live-folder-item-\(folderID.uuidString)-\(item.id)",
            contextMenuEntries: {
                actionOwner.liveFolderItemContextMenuEntries(item)
            },
            action: { actionOwner.openLiveFolderItem(item) },
            onDismiss: { actionOwner.dismissLiveFolderItem(item) }
        )
        .sidebarSelectedItemVisibility(
            .liveFolderItem(folderID: folderID, itemID: item.id),
            isSelected: isSelected,
            isEnabled: isInteractive
        )
    }
}

/// One shortcut-hosted split group.
struct TabFolderSplitGroupEntryView: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let space: Space
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    var isDropHighlighted = false

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        if !items.isEmpty {
            ShortcutHostedSplitGroupRow(
                group: group,
                items: items,
                spaceId: space.id,
                splitLayout: browserContext.splitLayout,
                emptySplitCreation: browserContext.emptySplitCreation,
                groupEditor: browserContext.splitGroupEditor,
                groupContextMenuActions: browserContext.splitGroupLifecycle
                    .contextMenuActions(for: group, in: windowState),
                isDropHighlighted: isDropHighlighted,
                isAppKitInteractionEnabled: isInteractive,
                faviconImageReader: browserContext.faviconImageReader,
                accessibilityID: "folder-shortcut-host-split-row-\(group.id.uuidString)",
                onActivateMember: { memberID in
                    browserContext.splitFocusCommands.focusGroup(
                        group.id,
                        memberID,
                        windowState.id
                    )
                },
                onUnloadGroup: {
                    browserContext.splitGroupLifecycle.unload(
                        group,
                        in: windowState
                    )
                },
                onCloseGroup: {
                    browserContext.splitGroupLifecycle.deleteSaved(group)
                }
            )
        }
    }

}
