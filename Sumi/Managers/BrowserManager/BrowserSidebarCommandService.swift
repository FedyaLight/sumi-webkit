import Foundation

@MainActor
final class BrowserSidebarCommandService {
    let editorPresentation: BrowserSidebarEditorPresentationOwner
    let chromeCommand: BrowserSidebarChromeCommandOwner
    let shortcutPromotion: BrowserSidebarShortcutPromotionOwner
    let folderCommand: BrowserSidebarFolderCommandOwner
    let tabCommand: BrowserSidebarTabCommandOwner
    let splitShortcutRouting: BrowserSidebarSplitShortcutRoutingOwner
    let spaceTransitionRouting: BrowserSpaceTransitionRoutingOwner
    let shortcutPinUnload: BrowserShortcutPinUnloadOwner
    let commandRouting: BrowserSidebarCommandRoutingOwner

    init(browserManager: BrowserManager) {
        editorPresentation = BrowserSidebarEditorPresentationOwner(
            sidebarPosition: { [weak browserManager] in
                browserManager?.sumiSettings?.sidebarPosition ?? .left
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings ?? SumiSettingsService()
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
                try browserManager?.tabManager.spaceLifecycleOwner.renameSpace(spaceId: spaceID, newName: name)
            },
            updateSpaceIcon: { [weak browserManager] spaceID, icon in
                try browserManager?.tabManager.spaceLifecycleOwner.updateSpaceIcon(spaceId: spaceID, icon: icon)
            },
            assignSpaceProfile: { [weak browserManager] spaceID, profileID in
                browserManager?.tabManager.profileAssignmentOwner.assign(spaceId: spaceID, toProfile: profileID)
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
        chromeCommand = BrowserSidebarChromeCommandOwner(
            showGradientEditor: { [weak browserManager] source in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor(source: source)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.chromeBundle.sidebarPresentationOwner.toggleSidebar(for: windowState)
            },
            openAppearanceSettings: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.commands.openSettingsTab(selecting: .appearance, in: windowState)
            },
            closeDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromeBundle.commands.closeDownloadsPopover(in: windowState)
            },
            toggleDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromeBundle.commands.toggleDownloadsPopover(in: windowState)
            }
        )
        shortcutPromotion = BrowserSidebarShortcutPromotionOwner(
            copyShortcutPinToEssentials: { [weak browserManager] pin, title, context in
                _ = browserManager?.tabManager.shortcutPinCommandOwner.copyShortcutPinToEssentials(
                    pin,
                    title: title,
                    context: context
                )
            }
        )
        folderCommand = BrowserSidebarFolderCommandOwner(
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
        tabCommand = BrowserSidebarTabCommandOwner(browserManager: browserManager)
        let tabManager = browserManager.tabManager
        let splitManager = browserManager.splitManager
        splitShortcutRouting = BrowserSidebarSplitShortcutRoutingOwner(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager ?? tabManager
            },
            splitManager: { [weak browserManager] in
                browserManager?.splitManager ?? splitManager
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSessionBundle.spaceStateOwner.space(for: spaceId)
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.windowSessionBundle.spaceStateOwner.setActiveSpace(space, in: windowState)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.visualMutationOwner.refreshCompositor(for: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.windowSessionBundle.visualMutationOwner.performImmediateVisualHandoffIfPossible(
                    in: windowState
                )
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.activationOwner.persistWindowSession(for: windowState)
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            }
        )
        spaceTransitionRouting = BrowserSpaceTransitionRoutingOwner(
            browserManager: browserManager
        )
        shortcutPinUnload = BrowserShortcutPinUnloadOwner(
            selectedShortcutLiveTab: { [weak browserManager] pinId, windowState in
                browserManager?.tabManager.shortcutPresentationOwner.selectedShortcutLiveTab(
                    for: pinId,
                    in: windowState
                )
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.tabLifecycleService.closeOrchestration.closeTab(tab, in: windowState)
            },
            userInitiatedUnload: { [weak browserManager] pinId, windowState, presentNotification in
                browserManager?.tabManager.shortcutLiveTabOwner.userInitiatedUnload(
                    pinId: pinId,
                    in: windowState,
                    presentNotification: presentNotification
                ) ?? false
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
        commandRouting = BrowserSidebarCommandRoutingOwner(
            folderCommand: folderCommand,
            chromeCommand: chromeCommand,
            tabCommand: tabCommand,
            splitShortcutRouting: splitShortcutRouting,
            shortcutPromotion: shortcutPromotion,
            shortcutPinUnload: shortcutPinUnload
        )
    }

    func makeSpaceTransitionActions() -> SidebarSpaceTransitionActions {
        spaceTransitionRouting.makeActions()
    }

    func makeCommandActions() -> SidebarBrowserCommandActions {
        commandRouting.makeActions()
    }
}
