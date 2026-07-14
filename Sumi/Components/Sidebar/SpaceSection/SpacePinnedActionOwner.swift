//
//  SpacePinnedActionOwner.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Owns the context-menu entry construction and folder/pin mutation actions
/// for the top-level space-pinned list, mirroring `TabFolderContextMenuActionOwner`'s
/// shape for the folder-scoped equivalent.
@MainActor
struct SpacePinnedActionOwner {
    let space: Space
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let contentMutationAnimation: Animation?

    func pinnedShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserContext.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: inventory.foldersByID.values
                .filter { !browserContext.liveFolderManager.isLiveFolder($0.id) },
            selectedFolderId: pin.folderId
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: spaceLifecycle.availableSpaces(isIncognito: false, ephemeralSpaces: []),
            selectedSpaceId: pin.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: pinProjection.executionProfileID(
                for: pin,
                currentSpaceID: space.id
            )
        )
        let addToEssentialsAction: (() -> Void)? = pinProjection.canAddToEssentials(
            url: pin.launchURL,
            in: windowState,
            spaceID: space.id
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions: SidebarSavedURLDriftActions? =
            selection.hasSavedURLDrift(pin, in: windowState)
                ? .init(
                    onBackToSavedURL: { resetShortcutPin(pin) },
                    onUseCurrentPageAsSavedURL: { _ = pinCommands.replaceSavedURLWithCurrent(pin, in: windowState) }
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
                        source: windowState.resolveSidebarPresentationSource(in: browserContext.windowRegistry()),
                        presentationActions: browserContext.presentationActions
                    )
                },
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource(in: browserContext.windowRegistry())
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
                        _ = pinCommands.assignExecutionProfile(pin, profileID: profileId)
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
            _ = pinCommands.ungroupFolder(folder.id)
        }
    }

    func deleteFolder(_ folder: TabFolder) {
        let childCount = pinCommands.recursiveChildCount(for: folder.id, in: space.id) ?? 0
        guard childCount == 0 else {
            confirmDeleteFolder(folder, childCount: childCount)
            return
        }

        mutatePinnedContent {
            _ = pinCommands.deleteFolder(folder.id)
        }
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        mutatePinnedContent {
            _ = pinCommands.remove(pin)
        }
    }

    func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.shellWindow(in: browserContext.windowRegistry()),
            themeContext: themeContext,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    func confirmDeleteFolder(_ folder: TabFolder, childCount: Int) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
            folderName: folder.name,
            childCount: childCount,
            window: windowState.shellWindow(in: browserContext.windowRegistry()),
            themeContext: themeContext,
            onDelete: {
                mutatePinnedContent {
                    _ = pinCommands.deleteFolder(folder.id)
                }
            }
        )
    }

    func resetShortcutPin(_ pin: ShortcutPin) {
        SidebarShortcutPinActions.resetToLaunchURL(
            pin,
            in: windowState,
            commands: pinCommands
        )
    }

    func unloadShortcutPin(_ pin: ShortcutPin) {
        browserContext.commands.unloadShortcutPin(pin, windowState)
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        guard let tab = pinCommands.materialize(
            pin,
            in: windowState,
            currentSpaceID: space.id
        ) else { return }
        browserContext.commands.requestUserTabActivation(tab, windowState)
    }

    func focusSplitGroup(_ groupID: UUID, memberID: SplitMemberID) {
        browserContext.commands.focusSplitGroup(groupID, memberID, windowState.id)
    }

    func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserContext.commands.openForegroundTab(pin.launchURL.absoluteString, windowState, space.id)
    }

    func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        mutatePinnedContent {
            _ = pinCommands.move(pin, toFolder: folderId)
        }
    }

    func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        mutatePinnedContent {
            _ = pinCommands.move(pin, toSpace: targetSpaceId)
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
            source ?? windowState.resolveSidebarPresentationSource(in: browserContext.windowRegistry())
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
        selection.presentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        selection.liveTab(for: pin.id, in: windowState)
    }
}
