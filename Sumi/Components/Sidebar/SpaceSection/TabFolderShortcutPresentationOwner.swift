//
//  TabFolderShortcutPresentationOwner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Resolves shortcut row presentation inputs for folder children.
@MainActor
struct TabFolderShortcutPresentationOwner {
    let pinProjection: SidebarPinFolderProjection
    let selection: SidebarWindowSelectionQuery
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let windowState: BrowserWindowState
    let selectionSnapshot: SidebarWindowSelectionSnapshot

    func faviconPartition(for pin: ShortcutPin) -> SumiFaviconPartition {
        pinProjection.faviconPartition(
            for: pin,
            currentSpaceID: windowState.currentSpaceId
        )
    }

    func runtimeAffordance(for pin: ShortcutPin) -> SumiLauncherRuntimeAffordanceState {
        selection.runtimeAffordance(
            for: pin,
            liveTab: launcherRuntime.liveTab(for: pin.id),
            in: windowState,
            selection: selectionSnapshot
        )
    }
}
