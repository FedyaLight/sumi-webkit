import Foundation

@MainActor
final class BrowserSidebarCommandService {
    let editorPresentation: BrowserSidebarEditorPresentationOwner
    let chromeCommand: BrowserSidebarChromeCommandOwner
    let shortcutPromotion: BrowserSidebarShortcutPromotionOwner
    let folderCommand: BrowserSidebarFolderCommandOwner
    let tabCommand: BrowserSidebarTabCommandOwner
    let splitShortcuts: SplitShortcutServices
    let spaceTransitionRouting: BrowserSpaceTransitionRoutingOwner
    let shortcutPinUnload: BrowserShortcutPinUnloadOwner
    let commandRouting: BrowserSidebarCommandRoutingOwner

    init(browserManager: BrowserManager) {
        editorPresentation = Self.makeEditorPresentation(browserManager)
        chromeCommand = Self.makeChromeCommands(browserManager)
        shortcutPromotion = Self.makeShortcutPromotion(browserManager)
        folderCommand = Self.makeFolderCommands(browserManager)
        tabCommand = BrowserSidebarTabCommandOwner(browserManager: browserManager)
        splitShortcuts = .live(browserManager: browserManager)
        spaceTransitionRouting = BrowserSpaceTransitionRoutingOwner(
            browserManager: browserManager
        )
        shortcutPinUnload = Self.makeShortcutPinUnload(browserManager: browserManager)
        commandRouting = BrowserSidebarCommandRoutingOwner(
            folderCommand: folderCommand,
            chromeCommand: chromeCommand,
            tabCommand: tabCommand,
            splitCommands: SidebarSplitCommands(
                services: splitShortcuts,
                splitGroup: { [weak browserManager] groupID in
                    browserManager?.tabManager.splitGroupStore.group(id: groupID)
                },
                windowState: { [weak browserManager] windowID in
                    browserManager?.windowRegistry?.windows[windowID]
                },
                liveTab: { [weak browserManager] memberID, windowState in
                    guard let tabManager = browserManager?.tabManager else {
                        return nil
                    }
                    switch memberID {
                    case .regularTab(let tabID):
                        return tabManager.tabCollectionMembershipOwner
                            .tab(for: tabID)
                    case .shortcutPin(let pinID):
                        return tabManager.shortcutPresentationOwner
                            .shortcutLiveTab(for: pinID, in: windowState.id)
                    }
                },
                closeTab: { [tabCommand] tab, windowState in
                    tabCommand.closeTab(tab, in: windowState)
                }
            ),
            shortcutPromotion: shortcutPromotion,
            shortcutPinUnload: shortcutPinUnload
        )
    }

    private static func makeEditorPresentation(
        _ browserManager: BrowserManager
    ) -> BrowserSidebarEditorPresentationOwner {
        BrowserSidebarEditorPresentationOwner(
            sidebarPosition: { [weak browserManager] in
                browserManager?.sumiSettings?.sidebarPosition ?? .left
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            sidebarHostRecoveryCoordinator: { [weak browserManager] in
                browserManager?.sidebarHostRecoveryCoordinator ?? SidebarHostRecoveryCoordinator()
            },
            renameSpace: { [weak browserManager] spaceID, name in
                try browserManager?.tabManager.spaceServices.catalog.renameSpace(spaceId: spaceID, newName: name)
            },
            updateSpaceIcon: { [weak browserManager] spaceID, icon in
                try browserManager?.tabManager.spaceServices.catalog.updateSpaceIcon(spaceId: spaceID, icon: icon)
            },
            assignSpaceProfile: { [weak browserManager] spaceID, profileID in
                browserManager?.tabManager.profileAssignments.spaces.assign(
                    spaceID: spaceID,
                    toProfile: profileID
                )
            },
            renameFolder: { [weak browserManager] folderID, name in
                browserManager?.tabManager.folderMutationOwner.renameFolder(folderID, newName: name)
            },
            updateFolderIcon: { [weak browserManager] folderID, icon in
                browserManager?.tabManager.folderMutationOwner.updateFolderIcon(folderID, icon: icon)
            },
            updateShortcutPin: { [weak browserManager] pin, title, launchURL, iconAsset in
                _ = browserManager?.tabManager.shortcutPinCommandOwner.updateShortcutPin(
                    pin,
                    title: title,
                    launchURL: launchURL,
                    iconAsset: .some(iconAsset)
                )
            }
        )
    }

    private static func makeChromeCommands(
        _ browserManager: BrowserManager
    ) -> BrowserSidebarChromeCommandOwner {
        BrowserSidebarChromeCommandOwner(
            showGradientEditor: { [weak browserManager] source in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor(source: source)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar(for: windowState)
            },
            openAppearanceSettings: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.settingsNavigation.openSettings(
                    selecting: .appearance,
                    in: windowState
                )
            },
            closeDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromeBundle.commands.closeDownloadsPopover(in: windowState)
            },
            toggleDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromeBundle.commands.toggleDownloadsPopover(in: windowState)
            }
        )
    }

    private static func makeShortcutPromotion(
        _ browserManager: BrowserManager
    ) -> BrowserSidebarShortcutPromotionOwner {
        BrowserSidebarShortcutPromotionOwner(
            copyShortcutPinToEssentials: { [weak browserManager] pin, title, context in
                _ = browserManager?.tabManager.shortcutPinCommandOwner.copyShortcutPinToEssentials(
                    pin,
                    title: title,
                    context: context
                )
            }
        )
    }

    private static func makeFolderCommands(
        _ browserManager: BrowserManager
    ) -> BrowserSidebarFolderCommandOwner {
        BrowserSidebarFolderCommandOwner(
            spaceForSidebarActions: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarActionOwner.spaceForSidebarActions(in: windowState)
            },
            createFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarActionOwner.createFolderInCurrentSpace(in: windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarActionOwner.createRSSLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubPRFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarActionOwner.createGitHubPRFolderInCurrentSpace(in: windowState)
            },
            createGitHubIssuesFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarActionOwner.createGitHubIssuesFolderInCurrentSpace(in: windowState)
            }
        )
    }

    private static func makeShortcutPinUnload(
        browserManager: BrowserManager
    ) -> BrowserShortcutPinUnloadOwner {
        BrowserShortcutPinUnloadOwner(
            shortcutLiveTab: { [weak browserManager] pinId, windowState in
                browserManager?.tabManager.shortcutPresentationOwner.shortcutLiveTab(
                    for: pinId,
                    in: windowState.id
                )
            },
            closeTab: { [weak browserManager] tab, windowState, presentNotification in
                browserManager?.tabLifecycleService.shortcutLiveTabClose.close(
                    tab,
                    in: windowState,
                    presentNotification: presentNotification
                ) ?? false
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
    }

    func makeSpaceTransitionActions() -> SidebarSpaceTransitionActions {
        spaceTransitionRouting.makeActions()
    }

    func makeCommandActions() -> SidebarBrowserCommandActions {
        commandRouting.makeActions()
    }
}
