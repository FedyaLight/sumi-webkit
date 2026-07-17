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

        return makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            actions: .init(
                duplicate: { duplicateShortcutPin(pin) },
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
                addToEssentials: addToEssentialsAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
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
                    .action(.init(title: "Hide Item", systemImage: "xmark", classification: .stateMutationNonStructural) {
                        browserContext.liveFolderManager.dismiss(item: item)
                    }),
                ],
            ]
        )
    }

    func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        if currentLiveFolderSource() != nil {
            return liveFolderHeaderContextMenuEntries()
        }

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

    private func liveFolderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        let source = currentLiveFolderSource()
        let statusTitle: String = {
            if let error = source?.lastErrorKind {
                return error.displayTitle
            }
            if let lastSuccessAt = source?.lastSuccessAt {
                return "Last Updated \(lastSuccessAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Not Updated Yet"
        }()

        let githubLoginSection: [SidebarContextMenuEntry]
        if source?.lastErrorKind == .notAuthenticated,
           source?.kind == .githubPullRequests || source?.kind == .githubIssues {
            githubLoginSection = [
                .action(.init(title: "Sign in to GitHub", systemImage: "person.crop.circle.badge.exclamationmark", classification: .presentationOnly) {
                    _ = browserContext.tabOpening.openNewTab(
                        url: "https://github.com/login",
                        context: .foreground(
                            windowState: windowState,
                            preferredSpaceId: space.id
                        )
                    )
                }),
            ]
        } else {
            githubLoginSection = []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: statusTitle, systemImage: "clock", isEnabled: false, classification: .presentationOnly) {}),
                    .action(.init(title: "Refresh Now", systemImage: "arrow.clockwise", classification: .stateMutationNonStructural) {
                        browserContext.liveFolderManager.refresh(folderId: folder.id)
                    }),
                    refreshIntervalSubmenu(for: source),
                ],
                githubLoginSection,
                [
                    .action(
                        .init(
                            title: "Delete Live Folder",
                            systemImage: "trash",
                            role: .destructive,
                            classification: .structuralMutation,
                            onAction: { mutationActions.deleteNestedFolder(folder) }
                        )
                    ),
                ],
            ]
        )
    }

    private func refreshIntervalSubmenu(for source: SumiLiveFolderSource?) -> SidebarContextMenuEntry {
        let options: [(title: String, seconds: TimeInterval)] = [
            ("15 Minutes", 15 * 60),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("6 Hours", 6 * 60 * 60),
        ]
        let currentInterval = source?.refreshIntervalSeconds

        return .submenu(
            title: "Refresh Every",
            systemImage: "timer",
            children: options.map { option in
                .action(
                    .init(
                        title: option.title,
                        systemImage: nil,
                        isEnabled: currentInterval != option.seconds,
                        state: currentInterval == option.seconds ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.setRefreshInterval(folderId: folder.id, seconds: option.seconds)
                    }
                )
            }
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

    private func currentLiveFolderSource() -> SumiLiveFolderSource? {
        browserContext.liveFolderManager.source(for: folder.id)
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
        _ = browserContext.shortcutCopy.copyToEssentials(
            pin,
            title: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            context: EssentialsShortcutPlacementOwner.TargetContext(
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
