//
//  TabFolderBodyEntryViews.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// One recursive child folder; the parent list owns only slot geometry.
struct TabFolderNestedFolderEntryView: View {
    let folder: TabFolder
    let browserContext: SidebarBrowserContext
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession
    let elevatedFolderIDs: Set<UUID>
    let isInteractive: Bool
    let parentFolderID: UUID
    let containerIndex: Int
    let nestingDepth: Int

    var body: some View {
        TabFolderView(
            folder: folder,
            browserContext: browserContext,
            space: space,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            spaceLifecycle: spaceLifecycle,
            shortcutRestoreSession: $shortcutRestoreSession,
            elevatedFolderIds: elevatedFolderIDs,
            isInteractive: isInteractive,
            parentFolderId: parentFolderID,
            containerIndex: containerIndex,
            nestingDepth: nestingDepth + 1
        )
    }
}

/// One saved shortcut with presentation resolved before entering the leaf.
struct TabFolderShortcutEntryView: View {
    let pin: ShortcutPin
    let placeholderGroup: SplitGroup?
    let placeholderIsSelected: Bool
    let liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let folderID: UUID
    let isInteractive: Bool
    let opacity: Double
    let contextMenuActionOwner: TabFolderContextMenuActionOwner
    let mutationActions: TabFolderMutationActions

    var body: some View {
        Group {
            if let placeholderGroup {
                ShortcutSplitPlaceholderRow(
                    pin: pin,
                    isSelected: placeholderIsSelected,
                    accessibilityID: "folder-split-placeholder-\(pin.id.uuidString)",
                    isAppKitInteractionEnabled: isInteractive,
                    action: {
                        mutationActions.focusSplitGroup(
                            placeholderGroup.id,
                            memberID: .shortcutPin(pin.id)
                        )
                    }
                )
            } else {
                ShortcutSidebarRow(
                    pin: pin,
                    liveTab: liveTab,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
                    runtimeAffordance: runtimeAffordance,
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
            }
        }
        .opacity(opacity)
    }
}

/// One live-folder result. Live-folder behavior stays on its existing owner.
struct TabFolderLiveItemEntryView: View {
    let item: SumiLiveFolderItem
    let folderID: UUID
    let isSelected: Bool
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
    }
}

/// One shortcut-hosted split group and its folder-scoped restore interaction.
struct TabFolderSplitGroupEntryView: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let folderLayoutAnimation: Animation?
    @Binding var shortcutRestoreSession: SpaceShortcutRestoreInteractionSession

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        if !items.isEmpty {
            ShortcutHostedSplitGroupRow(
                group: group,
                items: items,
                spaceId: space.id,
                splitLayout: browserContext.splitLayout,
                emptySplitCreation: browserContext.emptySplitCreation,
                isAppKitInteractionEnabled: isInteractive,
                faviconImageReader: browserContext.faviconImageReader,
                accessibilityID: "folder-shortcut-host-split-row-\(group.id.uuidString)",
                onActivateMember: { memberID in
                    browserContext.commands.focusSplitGroup(group.id, memberID, windowState.id)
                },
                onRestoreShortcutMember: { memberID in
                    browserContext.commands.restoreShortcutSplitMember(group.id, memberID, windowState.id)
                },
                onCloseMember: { memberID in
                    browserContext.commands.closeSplitMember(group.id, memberID, windowState.id)
                },
                onPrepareShortcutRestoreGap: prepareShortcutRestoreGap,
                onPerformShortcutRestoreWithPreparedGap: performShortcutRestoreWithPreparedGap
            )
        }
    }

    private func prepareShortcutRestoreGap(_ memberID: SplitMemberID) {
        let gap = SpaceShortcutRestorePlanner(
            inventory: inventory,
            space: space
        ).shortcutRestoreGap(groupID: group.id, memberID: memberID)
        guard let gap, folderLayoutAnimation != nil else { return }
        SpaceShortcutRestoreInteraction.prepare(
            session: $shortcutRestoreSession,
            gap: gap,
            animation: SidebarDropMotion.contentLayout
        )
    }

    private func performShortcutRestoreWithPreparedGap(
        _ memberID: SplitMemberID,
        _ update: () -> Void
    ) {
        let gap = SpaceShortcutRestorePlanner(
            inventory: inventory,
            space: space
        ).shortcutRestoreGap(groupID: group.id, memberID: memberID)
        SpaceShortcutRestoreInteraction.perform(
            session: $shortcutRestoreSession,
            gap: gap,
            update: update
        )
    }
}
