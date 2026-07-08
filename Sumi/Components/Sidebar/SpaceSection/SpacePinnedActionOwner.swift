//
//  SpacePinnedActionOwner.swift
//  Sumi
//

import SwiftUI

/// Owns the context-menu entry construction and folder/pin mutation actions
/// for the top-level space-pinned list, mirroring `TabFolderContextMenuActionOwner`'s
/// shape for the folder-scoped equivalent.
@MainActor
struct SpacePinnedActionOwner {
    let space: Space
    let browserContext: SidebarBrowserContext
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let contentMutationAnimation: Animation?

    func pinnedShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserContext.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: browserContext.tabManager.folderCollectionStateOwner.folders(for: space.id)
                .filter { !browserContext.liveFolderManager.isLiveFolder($0.id) },
            selectedFolderId: pin.folderId
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: browserContext.tabManager.spaceStateOwner.spaces,
            selectedSpaceId: pin.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: browserContext.tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: space.id
            )
        )
        let addToEssentialsAction: (() -> Void)? = browserContext.tabManager.essentialsShortcutPlacementOwner.canAddURL(
            pin.launchURL,
            using: .init(windowState: windowState, spaceId: space.id)
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions: SidebarSavedURLDriftActions? =
            browserContext.tabManager.shortcutPresentationOwner.shortcutHasDrifted(pin, in: windowState)
                ? .init(
                    onBackToSavedURL: { resetShortcutPin(pin) },
                    onUseCurrentPageAsSavedURL: { _ = browserContext.tabManager.shortcutPinCommandOwner.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                )
                : nil
        let unloadAction: (() -> Void)? = presentationState.isOpenLive
            ? { unloadShortcutPin(pin) }
            : nil
        let moveToSpaceAction: (UUID) -> Void = { targetSpaceId in
            moveShortcutPin(pin, toSpace: targetSpaceId)
        }

        return makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            actions: .init(
                duplicate: { duplicateShortcutPin(pin) },
                copyLink: { SidebarLinkActions.copyLink(pin.launchURL) },
                share: {
                    SidebarLinkActions.presentSharePicker(
                        for: pin.launchURL,
                        source: windowState.resolveSidebarPresentationSource(),
                        presentationActions: browserContext.presentationActions
                    )
                },
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in moveShortcutPin(pin, toFolder: folderId) }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: moveToSpaceAction
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        browserContext.tabManager.profileAssignmentOwner.assign(
                            shortcutPin: pin,
                            toExecutionProfile: profileId
                        )
                    }
                ),
                addToEssentials: addToEssentialsAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
        )
    }

    // MARK: - Folder Management

    func ungroupFolder(_ folder: TabFolder) {
        mutatePinnedContent {
            browserContext.tabManager.folderMutationOwner.ungroupFolder(folder.id)
        }
    }

    func deleteFolder(_ folder: TabFolder) {
        let childCount = browserContext.tabManager.spacePinnedStructureOwner.folderRecursiveChildCount(for: folder.id, in: space.id)
        guard childCount == 0 else {
            confirmDeleteFolder(folder, childCount: childCount)
            return
        }

        mutatePinnedContent {
            browserContext.tabManager.folderMutationOwner.deleteFolder(folder.id)
        }
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        mutatePinnedContent {
            browserContext.tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)
        }
    }

    func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.window,
            themeContext: themeContext,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    func confirmDeleteFolder(_ folder: TabFolder, childCount: Int) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
            folderName: folder.name,
            childCount: childCount,
            window: windowState.window,
            themeContext: themeContext,
            onDelete: {
                mutatePinnedContent {
                    browserContext.tabManager.folderMutationOwner.deleteFolder(folder.id)
                }
            }
        )
    }

    func resetShortcutPin(_ pin: ShortcutPin) {
        SidebarShortcutPinActions.resetToLaunchURL(
            pin,
            in: windowState,
            tabManager: browserContext.tabManager
        )
    }

    func unloadShortcutPin(_ pin: ShortcutPin) {
        if let current = browserContext.tabManager.shortcutPresentationOwner.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserContext.commands.closeTab(current, windowState)
            return
        }

        browserContext.tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserContext.commands.openForegroundTab(pin.launchURL.absoluteString, windowState, space.id)
    }

    func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserContext.tabManager.folderCollectionStateOwner.folder(by: folderId) else { return }
        let targetIndex = browserContext.tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutatePinnedContent {
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

    func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserContext.tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutatePinnedContent {
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

    func pinShortcutGlobally(_ pin: ShortcutPin) {
        browserContext.commands.pinShortcutGlobally(pin, windowState, space.id, activeShortcutTab(for: pin))
    }

    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        browserContext.presentationActions.showShortcutEditor(
            pin,
            windowState,
            themeContext,
            source ?? windowState.resolveSidebarPresentationSource()
        )
    }

    private func mutatePinnedContent(_ update: () -> Void) {
        if let contentMutationAnimation {
            withAnimation(contentMutationAnimation) {
                update()
            }
        } else {
            update()
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserContext.tabManager.shortcutPresentationOwner.shortcutPresentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserContext.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id)
    }
}
