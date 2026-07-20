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
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
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
                openInSplitView: makeSidebarShortcutOpenInSplitAction(
                    pin: pin,
                    browserContext: browserContext,
                    pinExecution: pinExecution,
                    windowState: windowState,
                    currentSpaceID: space.id
                ),
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
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: browserContext.windows.presentationSource(
                            for: windowState
                        )
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
                        _ = pinExecution.assignExecutionProfile(pin, profileID: profileId)
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
            _ = folderCommands.ungroupFolder(folder.id)
        }
    }

    func deleteFolder(_ folder: TabFolder) {
        let childCount = folderCommands.recursiveChildCount(for: folder.id, in: space.id) ?? 0
        guard childCount == 0 else {
            confirmDeleteFolder(folder, childCount: childCount)
            return
        }

        mutatePinnedContent {
            _ = folderCommands.deleteFolder(folder.id)
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
            window: browserContext.windows.shellWindow(for: windowState),
            themeContext: themeContext,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    func confirmDeleteFolder(_ folder: TabFolder, childCount: Int) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteFolder(
            folderName: folder.name,
            childCount: childCount,
            window: browserContext.windows.shellWindow(for: windowState),
            themeContext: themeContext,
            onDelete: {
                mutatePinnedContent {
                    _ = folderCommands.deleteFolder(folder.id)
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
        browserContext.shortcutPinUnload.unloadShortcutPin(
            pin,
            in: windowState
        )
    }

    func activateShortcutPin(_ pin: ShortcutPin) {
        guard let tab = pinExecution.materialize(
            pin,
            in: windowState,
            currentSpaceID: space.id
        ) else { return }
        browserContext.tabSelection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }

    func focusSplitGroup(_ groupID: UUID, memberID: SplitMemberID) {
        browserContext.splitFocusCommands.focusGroup(
            groupID,
            memberID,
            windowState.id
        )
    }

    func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserContext.tabOpening.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
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
        _ = browserContext.shortcutCopy.copyToEssentials(
            pin,
            title: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            context: EssentialsShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }

    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        browserContext.shortcutEditorPresentation.show(
            pin: pin,
            in: windowState,
            themeContext: themeContext,
            source: source ?? browserContext.windows.presentationSource(
                for: windowState
            )
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
