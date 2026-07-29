//
//  SpacePinnedListEntryViews.swift
//  Sumi
//

import SumiDomain
import SwiftUI

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
    }
}

/// One shortcut-hosted split row.
struct SpacePinnedSplitGroupEntryView: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let space: Space
    let browserContext: SidebarBrowserContext
    let pinProjection: SidebarPinFolderProjection
    let isInteractive: Bool
    let dragSnapshot: SidebarFolderDragSnapshot

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
                isAppKitInteractionEnabled: isInteractive,
                faviconPartition: {
                    pinProjection.faviconPartition(
                        for: $0,
                        currentSpaceID: space.id
                    )
                },
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
            .sidebarDropContainmentBackdrop(
                isVisible: dragSnapshot.isExistingSplitGroupTargeted(
                    memberIDs: group.memberIDs
                )
            )
        }
    }
}
