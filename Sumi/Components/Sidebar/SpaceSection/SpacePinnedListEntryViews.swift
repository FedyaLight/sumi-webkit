//
//  SpacePinnedListEntryViews.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Recursive folder entry plus the top-level drag geometry owned by its slot.
struct SpacePinnedFolderEntryView: View {
    let folder: TabFolder
    let presentation: SidebarFolderPresentationCell
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let browserContext: SidebarBrowserContext
    let elevatedFolderIDs: Set<UUID>
    let topLevelIndex: Int
    let geometryGeneration: Int
    let dragSnapshot: SidebarFolderDragSnapshot
    let isInteractive: Bool
    let reportsDropGeometry: Bool

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
            parentFolderId: nil,
            containerIndex: topLevelIndex,
            nestingDepth: 0,
            dragSnapshot: dragSnapshot
        )
        .sidebarTopLevelPinnedItemGeometry(
            itemId: folder.id,
            spaceId: space.id,
            topLevelIndex: topLevelIndex,
            generation: geometryGeneration,
            isActive: isInteractive && reportsDropGeometry
        )
        .sidebarZenCompositeLifecycleTransition(isEnabled: isInteractive)
    }
}

/// One top-level shortcut row with its already-resolved presentation values.
struct SpacePinnedShortcutEntryView: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let spaceID: UUID
    let isInteractive: Bool
    let opacity: Double
    let topLevelIndex: Int
    let geometryGeneration: Int
    let reportsDropGeometry: Bool
    let projectedSplitTarget: SidebarSplitPairingTarget?
    let actionOwner: SpacePinnedActionOwner

    var body: some View {
        ShortcutSidebarRow(
            pin: pin,
            liveTab: liveTab,
            faviconPartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            runtimeAffordance: runtimeAffordance,
            projectedSplitTarget: projectedSplitTarget,
            accessibilityID: "space-pinned-shortcut-\(pin.id.uuidString)",
            contextMenuEntries: { actionOwner.pinnedShortcutContextMenuEntries(pin) },
            action: { actionOwner.activateShortcutPin(pin) },
            dragSourceZone: .spacePinned(spaceID),
            dragHasTrailingActionExclusion: true,
            dragIsEnabled: isInteractive,
            onResetToLaunchURL: { actionOwner.resetShortcutPin(pin) },
            onUnload: { actionOwner.unloadShortcutPin(pin) },
            onRemove: { actionOwner.removeShortcutPin(pin) }
        )
        .opacity(opacity)
        .sidebarTopLevelPinnedItemGeometry(
            itemId: pin.id,
            spaceId: spaceID,
            topLevelIndex: topLevelIndex,
            splitPairingMemberIDs: [.shortcutPin(pin.id)],
            generation: geometryGeneration,
            isActive: isInteractive && reportsDropGeometry
        )
        .sidebarRowListItemTransition(isEnabled: isInteractive)
    }
}

/// One shortcut-hosted split row.
struct SpacePinnedSplitGroupEntryView: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let space: Space
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let topLevelIndex: Int
    let geometryGeneration: Int
    let dragSnapshot: SidebarFolderDragSnapshot
    let reportsDropGeometry: Bool

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
                isDropHighlighted:
                    dragSnapshot.isExistingSplitGroupTargeted(
                        memberIDs: group.memberIDs
                    ),
                isAppKitInteractionEnabled: isInteractive,
                faviconImageReader: browserContext.faviconImageReader,
                accessibilityID: "shortcut-host-split-row-\(group.id.uuidString)",
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
                    browserContext.splitGroupLifecycle.deleteSaved(
                        group,
                        in: windowState
                    )
                }
            )
            .sidebarTopLevelPinnedItemGeometry(
                itemId: group.id,
                spaceId: space.id,
                topLevelIndex: topLevelIndex,
                splitPairingMemberIDs: group.memberIDs,
                generation: geometryGeneration,
                isActive: isInteractive && reportsDropGeometry
            )
            .sidebarRowListItemTransition(isEnabled: isInteractive)
        }
    }

}
