//
//  FavoriteTileActionOwner.swift
//  Sumi
//

import SwiftUI

struct FavoriteTileContextMenuActions {
    let makeEntries: () -> [SidebarContextMenuEntry]

    func entries() -> [SidebarContextMenuEntry] {
        makeEntries()
    }
}

/// Owns the context-menu entry construction and mutation actions for an
/// favorite (pinned-grid) tile, mirroring `TabFolderContextMenuActionOwner`'s
/// shape for the folder-scoped equivalent.
@MainActor
struct FavoriteTileActionOwner {
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let contextMenuSpaceId: UUID?
    /// Wraps the tile-grid's animated-mutation policy (depends on window
    /// activation/profile-transition/reduce-motion state owned by `PinnedGrid`).
    let mutateContentLayout: (@escaping () -> Void) -> Void

    func contextMenuActions(for pin: ShortcutPin) -> FavoriteTileContextMenuActions {
        FavoriteTileContextMenuActions(makeEntries: {
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
                moveFavorite(pin, toSpace: targetSpaceId)
            }
            let spaceChoices = favoriteSpaceChoices
            let openInSplitView = makeSidebarShortcutOpenInSplitAction(
                pin: pin,
                browserContext: browserContext,
                pinExecution: pinExecution,
                windowState: windowState,
                currentSpaceID: windowState.currentSpaceId
            )

            return makeSidebarTabContextMenuEntries(
                role: .favorite,
                actions: .init(
                    duplicate: { duplicateAsRegularTab(pin) },
                    openInSplitView: openInSplitView,
                    copyLink: { SidebarLinkActions.copyLink(pin.launchURL) },
                    share: {
                        SidebarLinkActions.presentSharePicker(
                            for: pin.launchURL,
                            source: browserContext.windows.presentationSource(
                                for: windowState
                            ),
                            presentation: browserContext.sharingPresentation
                        )
                    },
                    edit: { presentShortcutLinkEditor(for: pin) },
                    folderTarget: .init(
                        choices: favoriteFolderChoices,
                        onSelect: { folderId in moveFavorite(pin, toFolder: folderId) }
                    ),
                    moveToSpace: .init(
                        choices: spaceChoices,
                        onSelect: moveToSpaceAction
                    ),
                    profileTarget: .init(
                        choices: profileChoices(for: pin),
                        onSelect: { profileId in
                            _ = pinExecution.assignExecutionProfile(pin, profileID: profileId)
                        }
                    ),
                    savedURLDrift: savedURLDriftActions,
                    unload: unloadAction,
                    deleteSavedTab: { confirmDeleteFavorite(pin) }
                )
            )
        })
    }

    func unload(_ pin: ShortcutPin) {
        browserContext.shortcutPinUnload.unloadShortcutPin(
            pin,
            in: windowState
        )
    }

    func duplicateAsRegularTab(_ pin: ShortcutPin) {
        _ = browserContext.tabOpening.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: windowState.currentSpaceId
            )
        )
    }

    func resetShortcutPin(_ pin: ShortcutPin) {
        SidebarShortcutPinActions.resetToLaunchURL(
            pin,
            in: windowState,
            commands: pinCommands
        )
    }

    func removeFromFavorite(_ pin: ShortcutPin) {
        mutateContentLayout {
            _ = pinCommands.remove(pin)
        }
    }

    func confirmDeleteFavorite(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .favorite,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: browserContext.windows.shellWindow(for: windowState),
            themeContext: themeContext,
            onDelete: { removeFromFavorite(pin) }
        )
    }

    private func presentShortcutLinkEditor(for pin: ShortcutPin) {
        browserContext.shortcutEditorPresentation.show(
            pin: pin,
            in: windowState,
            themeContext: themeContext,
            source: browserContext.windows.presentationSource(for: windowState)
        )
    }

    private func moveFavorite(_ pin: ShortcutPin, toFolder folderId: UUID) {
        mutateContentLayout {
            _ = pinCommands.move(pin, toFolder: folderId)
        }
    }

    private func moveFavorite(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        mutateContentLayout {
            _ = pinCommands.move(pin, toSpace: targetSpaceId)
        }
    }

    private var contextMenuSpace: Space? {
        guard let contextMenuSpaceId else { return nil }
        return spaceLifecycle.space(id: contextMenuSpaceId)
    }

    private var favoriteFolderChoices: [SidebarContextMenuChoice] {
        guard let contextMenuSpace else { return [] }
        return makeSidebarContextMenuFolderChoices(
            folders: contextMenuSpace.id == inventory.spaceID
                ? Array(inventory.foldersByID.values)
                : []
        )
    }

    private var favoriteSpaceChoices: [SidebarContextMenuChoice] {
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
