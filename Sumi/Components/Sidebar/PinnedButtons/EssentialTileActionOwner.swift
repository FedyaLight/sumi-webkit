//
//  EssentialTileActionOwner.swift
//  Sumi
//

import SwiftUI

struct EssentialTileContextMenuActions {
    let makeEntries: () -> [SidebarContextMenuEntry]

    func entries() -> [SidebarContextMenuEntry] {
        makeEntries()
    }
}

/// Owns the context-menu entry construction and mutation actions for an
/// essentials (pinned-grid) tile, mirroring `TabFolderContextMenuActionOwner`'s
/// shape for the folder-scoped equivalent.
@MainActor
struct EssentialTileActionOwner {
    let browserContext: SidebarBrowserContext
    let inventory: SidebarInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let contextMenuSpaceId: UUID?
    /// Wraps the tile-grid's animated-mutation policy (depends on window
    /// activation/profile-transition/reduce-motion state owned by `PinnedGrid`).
    let mutateContentLayout: (@escaping () -> Void) -> Void

    func contextMenuActions(for pin: ShortcutPin) -> EssentialTileContextMenuActions {
        EssentialTileContextMenuActions(makeEntries: {
            let savedURLDriftActions: SidebarSavedURLDriftActions? =
                selection.hasSavedURLDrift(pin, in: windowState)
                    ? .init(
                        onBackToSavedURL: { resetShortcutPin(pin) },
                        onUseCurrentPageAsSavedURL: { _ = pinCommands.replaceSavedURLWithCurrent(pin, in: windowState) }
                    )
                    : nil
            let unloadAction: (() -> Void)? = pinPresentationState(pin).isOpenLive
                ? { unload(pin) }
                : nil
            let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
                moveEssential(pin, toSpace: targetSpaceId)
            }
            let spaceChoices = essentialSpaceChoices

            return makeSidebarTabContextMenuEntries(
                role: .essential,
                actions: .init(
                    duplicate: { duplicateAsRegularTab(pin) },
                    copyLink: { SidebarLinkActions.copyLink(pin.launchURL) },
                    share: {
                        SidebarLinkActions.presentSharePicker(
                            for: pin.launchURL,
                            source: windowState.resolveSidebarPresentationSource(in: browserContext.windowRegistry()),
                            presentationActions: browserContext.presentationActions
                        )
                    },
                    edit: { presentShortcutLinkEditor(for: pin) },
                    folderTarget: .init(
                        choices: essentialFolderChoices,
                        onSelect: { folderId in moveEssential(pin, toFolder: folderId) }
                    ),
                    moveToSpace: .init(
                        choices: spaceChoices,
                        onSelect: moveToSpaceAction
                    ),
                    profileTarget: .init(
                        choices: profileChoices(for: pin),
                        onSelect: { profileId in
                            _ = pinCommands.assignExecutionProfile(pin, profileID: profileId)
                        }
                    ),
                    savedURLDrift: savedURLDriftActions,
                    unload: unloadAction,
                    deleteSavedTab: { confirmDeleteEssential(pin) }
                )
            )
        })
    }

    func unload(_ pin: ShortcutPin) {
        browserContext.commands.unloadShortcutPin(pin, windowState)
    }

    func duplicateAsRegularTab(_ pin: ShortcutPin) {
        _ = browserContext.commands.openForegroundTab(
            pin.launchURL.absoluteString,
            windowState,
            windowState.currentSpaceId
        )
    }

    func resetShortcutPin(_ pin: ShortcutPin) {
        SidebarShortcutPinActions.resetToLaunchURL(
            pin,
            in: windowState,
            commands: pinCommands
        )
    }

    func removeFromEssentials(_ pin: ShortcutPin) {
        mutateContentLayout {
            _ = pinCommands.remove(pin)
        }
    }

    func confirmDeleteEssential(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .essential,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.shellWindow(in: browserContext.windowRegistry()),
            themeContext: themeContext,
            onDelete: { removeFromEssentials(pin) }
        )
    }

    private func presentShortcutLinkEditor(for pin: ShortcutPin) {
        browserContext.presentationActions.showShortcutEditor(
            pin,
            windowState,
            themeContext,
            windowState.resolveSidebarPresentationSource(in: browserContext.windowRegistry())
        )
    }

    private func moveEssential(_ pin: ShortcutPin, toFolder folderId: UUID) {
        mutateContentLayout {
            _ = pinCommands.move(pin, toFolder: folderId)
        }
    }

    private func moveEssential(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        mutateContentLayout {
            _ = pinCommands.move(pin, toSpace: targetSpaceId)
        }
    }

    private var contextMenuSpace: Space? {
        guard let contextMenuSpaceId else { return nil }
        return spaceLifecycle.space(id: contextMenuSpaceId)
    }

    private var essentialFolderChoices: [SidebarContextMenuChoice] {
        guard let contextMenuSpace else { return [] }
        return makeSidebarContextMenuFolderChoices(
            folders: Array(inventory.snapshot(for: contextMenuSpace.id)?.foldersByID.values ?? Dictionary<UUID, TabFolder>().values)
        )
    }

    private var essentialSpaceChoices: [SidebarContextMenuChoice] {
        makeSidebarContextMenuSpaceChoices(
            spaces: spaceLifecycle.availableSpaces(isIncognito: false, ephemeralSpaces: [])
        )
    }

    private func profileChoices(for pin: ShortcutPin) -> [SidebarContextMenuChoice] {
        makeSidebarContextMenuProfileChoices(
            profiles: browserContext.profileManager.profiles,
            selectedProfileId: pinProjection.executionProfileID(
                for: pin,
                currentSpaceID: contextMenuSpace?.id
            )
        )
    }

    private func pinPresentationState(_ pin: ShortcutPin) -> ShortcutPresentationState {
        selection.presentationState(for: pin, in: windowState)
    }
}
