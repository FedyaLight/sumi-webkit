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
    let regularTabs: any SidebarRegularTabsControlling
    let browserContext: SidebarBrowserContext
    let windowState: BrowserWindowState
    let firstTabID: UUID?
    let lastTabID: UUID?

    func activate(_ tab: Tab) {
        browserContext.commands.requestUserTabActivation(tab, windowState)
    }

    func close(_ tab: Tab) {
        browserContext.commands.closeTab(tab, windowState)
    }

    func contextMenuEntries(
        for tab: Tab,
        close: @escaping () -> Void
    ) -> [SidebarContextMenuEntry] {
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: regularTabs.userFolders(for: space.id)
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: regularTabs.spaces,
            selectedSpaceId: tab.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: browserContext.profileManager.profiles,
            selectedProfileId: tab.profileId ?? space.profileId
        )
        let moveUpAction: (() -> Void)? = firstTabID == tab.id
            ? nil
            : { browserContext.commands.moveTabUp(tab.id) }
        let moveDownAction: (() -> Void)? = lastTabID == tab.id
            ? nil
            : { browserContext.commands.moveTabDown(tab.id) }
        let pinToSpaceAction: (() -> Void)? = tab.isPinned || tab.isSpacePinned
            ? nil
            : { regularTabs.pinTabToSpace(tab, spaceId: space.id) }
        let addToEssentialsAction: (() -> Void)? = regularTabs.canAddToEssentials(
            tab,
            in: space,
            windowState: windowState
        )
            ? { regularTabs.addTabToEssentials(tab, in: space, windowState: windowState) }
            : nil
        let closeTabsBelowAction: (() -> Void)? = !tab.isPinned
            && !tab.isSpacePinned
            && tab.spaceId != nil
            ? { regularTabs.closeAllTabsBelow(tab) }
            : nil

        return makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: .init(
                duplicate: { browserContext.commands.duplicateTab(tab, windowState) },
                copyLink: { SidebarLinkActions.copyLink(tab.url) },
                share: {
                    SidebarLinkActions.presentSharePicker(
                        for: tab.url,
                        source: windowState.resolveSidebarPresentationSource(
                            in: browserContext.windowRegistry()
                        ),
                        presentationActions: browserContext.presentationActions
                    )
                },
                rename: { tab.startRenaming() },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { regularTabs.moveTabToFolder(tab, folderId: $0) }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: { regularTabs.moveTab(tab.id, to: $0) }
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { regularTabs.assign(tab, toProfile: $0) }
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
