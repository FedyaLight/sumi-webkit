//
//  SpaceRegularTabActionOwner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Method-based behavior boundary for one space's regular-tab rows.
///
/// The list keeps its animation state; this owner keeps browser commands and
/// context-menu construction out of the rendering leaf without expanding them
/// back into a closure bag.
@MainActor
struct SpaceRegularTabActionOwner {
    let space: Space
    let catalog: SidebarRegularTabCatalog
    let targets: SidebarRegularTabTargetQuery
    let lifecycleCommands: SidebarRegularTabLifecycleCommands
    let shortcutCommands: SidebarRegularTabShortcutCommands
    let placementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let windowState: BrowserWindowState
    let firstTabID: UUID?
    let lastTabID: UUID?

    func activate(_ tab: Tab) {
        browserContext.tabSelection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }

    func close(_ tab: Tab) {
        browserContext.tabClose.closeTab(tab, in: windowState)
    }

    func contextMenuEntries(
        for tab: Tab,
        close: @escaping () -> Void
    ) -> [SidebarContextMenuEntry] {
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: targets.userFolders(for: space.id)
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: catalog.allSpaces,
            selectedSpaceId: tab.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: browserContext.profileManager.profiles,
            selectedProfileId: tab.profileId ?? space.profileId
        )
        let moveUpAction: (() -> Void)? = firstTabID == tab.id
            ? nil
            : { browserContext.regularTabs.moveTabUp(tab.id) }
        let moveDownAction: (() -> Void)? = lastTabID == tab.id
            ? nil
            : { browserContext.regularTabs.moveTabDown(tab.id) }
        let pinToSpaceAction: (() -> Void)? = tab.isPinned || tab.isSpacePinned
            ? nil
            : { shortcutCommands.pinTabToSpace(tab, spaceID: space.id) }
        let addToEssentialsAction: (() -> Void)? = targets.canAddToEssentials(
            tab,
            in: space,
            windowState: windowState
        )
            ? {
                shortcutCommands.addTabToEssentials(
                    tab,
                    in: space,
                    windowState: windowState
                )
            }
            : nil
        let closeTabsBelowAction: (() -> Void)? = !tab.isPinned
            && !tab.isSpacePinned
            && tab.spaceId != nil
            ? { lifecycleCommands.closeAllTabsBelow(tab) }
            : nil

        return makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: .init(
                duplicate: {
                    browserContext.tabOpening.duplicateTab(
                        tab,
                        in: windowState
                    )
                },
                copyLink: { SidebarLinkActions.copyLink(tab.url) },
                share: {
                    SidebarLinkActions.presentSharePicker(
                        for: tab.url,
                        source: browserContext.windows.presentationSource(
                            for: windowState
                        ),
                        presentation: browserContext.sharingPresentation
                    )
                },
                rename: { tab.startRenaming() },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: {
                        placementCommands.moveTabToFolder(tab, folderID: $0)
                    }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: { placementCommands.moveTab(tab.id, to: $0) }
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: {
                        placementCommands.assign(tab, toProfile: $0)
                    }
                ),
                moveUp: moveUpAction,
                moveDown: moveDownAction,
                pinToSpace: pinToSpaceAction,
                addToEssentials: addToEssentialsAction,
                closeTabsBelow: closeTabsBelowAction,
                close: close
            )
        )
    }
}
