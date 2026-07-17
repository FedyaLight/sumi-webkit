//
//  SpaceTitleActionOwner.swift
//  Sumi
//

import Foundation

/// Builds `SpaceTitleActions` without threading `tabManager` through `SpaceView`.
@MainActor
struct SpaceTitleActionOwner {
    let browserContext: SidebarBrowserContext
    let spaceLifecycle: SidebarSpaceLifecycle
    let space: Space
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let themeContext: ResolvedThemeContext

    var actions: SpaceTitleActions {
        SpaceTitleActions(
            canDeleteSpace: spaceLifecycle.canDeleteSpace(),
            renameSpace: { newName in
                do {
                    try spaceLifecycle.renameSpace(space.id, to: newName)
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to rename space \(space.id.uuidString):", error)
                }
            },
            updateSpaceIcon: { icon in
                do {
                    try spaceLifecycle.updateSpaceIcon(space.id, to: icon)
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to update space icon \(space.id.uuidString):", error)
                }
            },
            persistCommittedEmoji: { icon in
                do {
                    try spaceLifecycle.updateSpaceIcon(space.id, to: icon)
                } catch {
                    RuntimeDiagnostics.emit("⚠️ Failed to persist space icon \(space.id.uuidString):", error)
                }
            },
            editSpace: {
                browserContext.spaceEditorPresentation.show(
                    space: space,
                    in: windowState,
                    themeContext: themeContext,
                    source: windowState.resolveSidebarPresentationSource(
                        in: windowRegistry
                    )
                )
            },
            changeTheme: {
                browserContext.workspaceThemeEditor.showGradientEditor(
                    for: space,
                    source: windowState.resolveSidebarPresentationSource(
                        in: windowRegistry
                    )
                )
            },
            deleteSpace: {
                browserContext.spaceDeletionPresentation.confirmDelete(
                    space,
                    in: windowState
                )
            }
        )
    }
}
