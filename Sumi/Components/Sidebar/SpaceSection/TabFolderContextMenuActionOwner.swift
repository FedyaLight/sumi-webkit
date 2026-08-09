//
//  TabFolderContextMenuActionOwner.swift
//  Sumi
//
//

import SwiftUI

@MainActor
struct TabFolderContextMenuActionOwner {
    let folder: TabFolder
    let space: Space
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
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
    let folderLayoutAnimation: Animation?
    let mutationActions: TabFolderMutationActions

    func folderShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserContext.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: inventory.foldersByID.values
                .filter { !$0.isLiveFolder },
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
        let addToFavoriteAction: (() -> Void)? = pinProjection.canAddToFavorite(
            url: pin.launchURL,
            in: windowState,
            spaceID: space.id
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions = savedURLDriftActions(for: pin)
        let unloadAction: (() -> Void)? = presentationState.isOpenLive
            ? { unloadShortcutPin(pin) }
            : nil

        return makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
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
                    onSelect: { targetSpaceId in moveShortcutPin(pin, toSpace: targetSpaceId) }
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        _ = pinExecution.assignExecutionProfile(pin, profileID: profileId)
                    }
                ),
                addToFavorite: addToFavoriteAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
        )
    }

    private func savedURLDriftActions(for pin: ShortcutPin) -> SidebarSavedURLDriftActions? {
        guard selection.hasSavedURLDrift(pin, in: windowState) else {
            return nil
        }
        return .init(
            onBackToSavedURL: { resetShortcutPin(pin) },
            onUseCurrentPageAsSavedURL: { _ = pinCommands.replaceSavedURLWithCurrent(pin, in: windowState) }
        )
    }

    func liveFolderItemContextMenuEntries(_ item: SumiLiveFolderItem) -> [SidebarContextMenuEntry] {
        guard let url = item.url else {
            return []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: "Open", systemImage: "arrow.up.right.square", classification: .presentationOnly) {
                        browserContext.liveFolderManager.open(item: item, in: windowState)
                    }),
                    .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly) {
                        SidebarLinkActions.copyLink(url)
                    }),
                    .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly) {
                        SidebarLinkActions.presentSharePicker(
                            for: url,
                            source: browserContext.windows.presentationSource(
                                for: windowState
                            ),
                            presentation: browserContext.sharingPresentation
                        )
                    }),
                ],
                [
                    .action(.init(title: "Remove from Folder", systemImage: "rectangle.portrait.and.arrow.right", classification: .structuralMutation) {
                        browserContext.liveFolderManager.detach(item: item)
                    }),
                    .action(.init(title: "Hide Item", systemImage: "xmark", classification: .stateMutationNonStructural) {
                        browserContext.liveFolderManager.dismiss(item: item)
                    }),
                ],
            ]
        )
    }

    func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        let folderEntries = folderManagementContextMenuEntries()
        guard currentLiveFolderSource() != nil else {
            return folderEntries
        }
        return liveFolderHeaderContextMenuEntries(followedBy: folderEntries)
    }

    func folderManagementContextMenuEntries() -> [SidebarContextMenuEntry] {
        let unloadActiveTabsAction: (() -> Void)?
        if folderHasLiveSavedTabs {
            unloadActiveTabsAction = unloadActiveFolderTabs
        } else {
            unloadActiveTabsAction = nil
        }

        return makeFolderHeaderContextMenuEntries(
            actions: .init(
                edit: {
                    browserContext.folderEditorPresentation.show(
                        folder: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: browserContext.windows.presentationSource(
                            for: windowState
                        )
                    )
                },
                alphabetize: alphabetizeTabs,
                unloadActiveTabs: unloadActiveTabsAction,
                ungroup: { mutationActions.ungroupNestedFolder(folder) },
                delete: { mutationActions.deleteNestedFolder(folder) }
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

    func unloadShortcutPin(_ pin: ShortcutPin) {
        browserContext.shortcutPinUnload.unloadShortcutPin(
            pin,
            in: windowState
        )
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        mutateFolderContent {
            _ = pinCommands.remove(pin)
        }
    }

    func openLiveFolderItem(_ item: SumiLiveFolderItem) {
        browserContext.liveFolderManager.open(item: item, in: windowState)
    }

    func dismissLiveFolderItem(_ item: SumiLiveFolderItem) {
        browserContext.liveFolderManager.dismiss(item: item)
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

    private func alphabetizeTabs() {
        withAnimation(folderLayoutAnimation) {
            _ = folderCommands.alphabetizeFolder(folder.id, in: space.id)
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        selection.presentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        selection.liveTab(for: pin.id, in: windowState)
    }

    private func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: browserContext.windows.shellWindow(for: windowState),
            themeContext: themeContext,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    private func mutateFolderContent(_ update: () -> Void) {
        if let animation = folderLayoutAnimation {
            withAnimation(animation, update)
        } else {
            update()
        }
    }

    private func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserContext.tabOpening.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        mutateFolderContent {
            _ = pinCommands.move(pin, toFolder: folderId)
        }
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        mutateFolderContent {
            _ = pinCommands.move(pin, toSpace: targetSpaceId)
        }
    }

    private func pinShortcutGlobally(_ pin: ShortcutPin) {
        _ = browserContext.shortcutCopy.copyToFavorite(
            pin,
            title: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            context: FavoriteShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }

    private var folderHasLiveSavedTabs: Bool {
        folderHasLiveSavedTabsHelper(folderId: folder.id)
    }

    private func folderHasLiveSavedTabsHelper(folderId: UUID) -> Bool {
        if let directPins = folderPinsByFolderId[folderId],
           directPins.contains(where: { selection.liveTab(for: $0.id, in: windowState) != nil }) {
            return true
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if folderHasLiveSavedTabsHelper(folderId: child.id) {
                    return true
                }
            }
        }
        return false
    }

    private var descendantShortcutPins: [ShortcutPin] {
        descendantShortcutPins(in: folder.id, visited: [])
    }

    private func descendantShortcutPins(in folderId: UUID, visited: Set<UUID>) -> [ShortcutPin] {
        guard !visited.contains(folderId) else { return [] }
        var nextVisited = visited
        nextVisited.insert(folderId)

        let directPins = folderPinsByFolderId[folderId] ?? []
        let nestedPins = (childFoldersByParentId[folderId] ?? []).flatMap { childFolder in
            descendantShortcutPins(in: childFolder.id, visited: nextVisited)
        }
        return directPins + nestedPins
    }

    private func unloadActiveFolderTabs() {
        browserContext.shortcutPinUnload.unloadShortcutPins(
            descendantShortcutPins,
            in: windowState
        )
    }
}
