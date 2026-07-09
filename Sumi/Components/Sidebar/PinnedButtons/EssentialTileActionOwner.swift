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
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let contextMenuSpaceId: UUID?
    /// Wraps the tile-grid's animated-mutation policy (depends on window
    /// activation/profile-transition/reduce-motion state owned by `PinnedGrid`).
    let mutateContentLayout: (@escaping () -> Void) -> Void

    func contextMenuActions(for pin: ShortcutPin) -> EssentialTileContextMenuActions {
        EssentialTileContextMenuActions(makeEntries: {
            let savedURLDriftActions: SidebarSavedURLDriftActions? =
                browserContext.tabManager.shortcutPresentationOwner.shortcutHasDrifted(pin, in: windowState)
                    ? .init(
                        onBackToSavedURL: { resetShortcutPin(pin) },
                        onUseCurrentPageAsSavedURL: { _ = browserContext.tabManager.shortcutPinCommandOwner.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
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
                            source: windowState.resolveSidebarPresentationSource(),
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
                            browserContext.tabManager.profileAssignmentOwner.assign(
                                shortcutPin: pin,
                                toExecutionProfile: profileId
                            )
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
            tabManager: browserContext.tabManager
        )
    }

    func removeFromEssentials(_ pin: ShortcutPin) {
        mutateContentLayout {
            browserContext.tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)
        }
    }

    func confirmDeleteEssential(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .essential,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.shellWindow(in: nil),
            themeContext: themeContext,
            onDelete: { removeFromEssentials(pin) }
        )
    }

    private func presentShortcutLinkEditor(for pin: ShortcutPin) {
        browserContext.presentationActions.showShortcutEditor(
            pin,
            windowState,
            themeContext,
            windowState.resolveSidebarPresentationSource()
        )
    }

    private func moveEssential(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserContext.tabManager.folderCollectionStateOwner.folder(by: folderId) else { return }
        let targetIndex = browserContext.tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutateContentLayout {
            _ = browserContext.tabManager.shortcutPinCommandOwner.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                index: targetIndex
            )
        }
    }

    private func moveEssential(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserContext.tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutateContentLayout {
            _ = browserContext.tabManager.shortcutPinCommandOwner.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: targetIndex
            )
        }
    }

    private var contextMenuSpace: Space? {
        guard let contextMenuSpaceId else { return nil }
        return browserContext.tabManager.spaceStateOwner.spaces.first { $0.id == contextMenuSpaceId }
    }

    private var essentialFolderChoices: [SidebarContextMenuChoice] {
        guard let contextMenuSpace else { return [] }
        return makeSidebarContextMenuFolderChoices(
            folders: browserContext.tabManager.folderCollectionStateOwner.folders(for: contextMenuSpace.id)
        )
    }

    private var essentialSpaceChoices: [SidebarContextMenuChoice] {
        makeSidebarContextMenuSpaceChoices(
            spaces: browserContext.tabManager.spaceStateOwner.spaces
        )
    }

    private func profileChoices(for pin: ShortcutPin) -> [SidebarContextMenuChoice] {
        makeSidebarContextMenuProfileChoices(
            profiles: browserContext.profileManager.profiles,
            selectedProfileId: browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: contextMenuSpace?.id
            )
        )
    }

    private func pinPresentationState(_ pin: ShortcutPin) -> ShortcutPresentationState {
        browserContext.tabManager.shortcutPresentationOwner.shortcutPresentationState(for: pin, in: windowState)
    }
}
