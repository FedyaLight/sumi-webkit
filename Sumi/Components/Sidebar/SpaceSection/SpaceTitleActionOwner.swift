//
//  SpaceTitleActionOwner.swift
//  Sumi
//

import Foundation

/// Builds `SpaceTitleActions` without threading `tabManager` through `SpaceView`.
@MainActor
struct SpaceTitleActionOwner {
    let browserContext: SidebarBrowserContext
    let space: Space
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let themeContext: ResolvedThemeContext

    var actions: SpaceTitleActions {
        SpaceTitleActions(
            canDeleteSpace: browserContext.tabManager.spaceStateOwner.spaces.count > 1,
            renameSpace: { newName in
                do {
                    try browserContext.tabManager.spaceServices.catalog.renameSpace(
                        spaceId: space.id,
                        newName: newName
                    )
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to rename space \(space.id.uuidString):", error)
                }
            },
            updateSpaceIcon: { icon in
                do {
                    try browserContext.tabManager.spaceServices.catalog.updateSpaceIcon(spaceId: space.id, icon: icon)
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to update space icon \(space.id.uuidString):", error)
                }
            },
            persistCommittedEmoji: { _ in
                browserContext.tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
                browserContext.tabManager.structuralPersistence.scheduleStructuralPersistence()
            },
            editSpace: {
                browserContext.presentationActions.showSpaceEditor(
                    space,
                    windowState,
                    themeContext,
                    windowState.resolveSidebarPresentationSource(in: windowRegistry)
                )
            },
            changeTheme: {
                browserContext.presentationActions.showGradientEditorForSpace(
                    space,
                    windowState.resolveSidebarPresentationSource(in: windowRegistry)
                )
            },
            deleteSpace: {
                browserContext.presentationActions.confirmDeleteSpace(
                    space,
                    windowState
                )
            }
        )
    }
}
