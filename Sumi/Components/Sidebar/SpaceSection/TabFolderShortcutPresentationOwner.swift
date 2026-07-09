//
//  TabFolderShortcutPresentationOwner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Resolves shortcut row presentation inputs for folder children.
@MainActor
struct TabFolderShortcutPresentationOwner {
    let browserContext: SidebarBrowserContext
    let windowState: BrowserWindowState

    func faviconPartition(for pin: ShortcutPin) -> SumiFaviconPartition {
        browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
            for: pin,
            currentSpaceId: windowState.currentSpaceId
        )
    }

    func runtimeAffordance(for pin: ShortcutPin) -> SumiLauncherRuntimeAffordanceState {
        browserContext.tabManager.shortcutPresentationOwner.shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState
        )
    }
}
