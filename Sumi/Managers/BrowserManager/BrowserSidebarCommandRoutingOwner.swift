import Foundation

@MainActor
final class BrowserSidebarCommandRoutingOwner {
    private let folderCommand: BrowserSidebarFolderCommandOwner
    private let chromeCommand: BrowserSidebarChromeCommandOwner
    private let tabCommand: BrowserSidebarTabCommandOwner
    private let splitShortcutRouting: any BrowserSidebarSplitShortcutRouting
    private let shortcutPromotion: BrowserSidebarShortcutPromotionOwner
    private let shortcutPinUnload: BrowserShortcutPinUnloadOwner

    init(
        folderCommand: BrowserSidebarFolderCommandOwner,
        chromeCommand: BrowserSidebarChromeCommandOwner,
        tabCommand: BrowserSidebarTabCommandOwner,
        splitShortcutRouting: any BrowserSidebarSplitShortcutRouting,
        shortcutPromotion: BrowserSidebarShortcutPromotionOwner,
        shortcutPinUnload: BrowserShortcutPinUnloadOwner
    ) {
        self.folderCommand = folderCommand
        self.chromeCommand = chromeCommand
        self.tabCommand = tabCommand
        self.splitShortcutRouting = splitShortcutRouting
        self.shortcutPromotion = shortcutPromotion
        self.shortcutPinUnload = shortcutPinUnload
    }

    func makeActions() -> SidebarBrowserCommandActions {
        SidebarBrowserCommandActions(
            canCreateFolderInCurrentSpace: { [folderCommand] windowState in
                folderCommand.canCreateFolderInCurrentSpace(in: windowState)
            },
            showGradientEditor: { [chromeCommand] source in
                chromeCommand.showGradientEditor(source: source)
            },
            toggleSidebar: { [chromeCommand] windowState in
                chromeCommand.toggleSidebar(in: windowState)
            },
            openAppearanceSettings: { [chromeCommand] windowState in
                chromeCommand.openAppearanceSettings(in: windowState)
            },
            closeDownloadsPopover: { [chromeCommand] windowState in
                chromeCommand.closeDownloadsPopover(in: windowState)
            },
            requestUserTabActivation: { [tabCommand] tab, windowState in
                tabCommand.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [tabCommand] tab, windowState in
                tabCommand.closeTab(tab, in: windowState)
            },
            moveTabUp: { [tabCommand] tabId in
                tabCommand.moveTabUp(tabId)
            },
            moveTabDown: { [tabCommand] tabId in
                tabCommand.moveTabDown(tabId)
            },
            focusSplitGroup: { [splitShortcutRouting] group, windowState in
                splitShortcutRouting.focusSplitGroup(group, in: windowState)
            },
            restoreShortcutSplitMember: { [splitShortcutRouting] memberId, group, windowState in
                splitShortcutRouting.restoreShortcutSplitMember(
                    memberId,
                    from: group,
                    in: windowState
                )
            },
            openForegroundTab: { [tabCommand] url, windowState, preferredSpaceId in
                tabCommand.openForegroundTab(
                    url,
                    in: windowState,
                    preferredSpaceId: preferredSpaceId
                )
            },
            openNewTabOrFloatingBar: { [tabCommand] windowState in
                tabCommand.openNewTabOrFloatingBar(in: windowState)
            },
            duplicateTab: { [tabCommand] tab, windowState in
                tabCommand.duplicateTab(tab, in: windowState)
            },
            pinShortcutGlobally: { [shortcutPromotion] pin, windowState, spaceId, liveTab in
                shortcutPromotion.pinShortcutGlobally(
                    pin,
                    in: windowState,
                    spaceId: spaceId,
                    liveTab: liveTab
                )
            },
            toggleDownloadsPopover: { [chromeCommand] windowState in
                chromeCommand.toggleDownloadsPopover(in: windowState)
            },
            createFolderInCurrentSpace: { [folderCommand] windowState in
                folderCommand.createFolderInCurrentSpace(in: windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [folderCommand] windowState in
                folderCommand.createRSSLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubPRFolderInCurrentSpace: { [folderCommand] windowState in
                folderCommand.createGitHubPRFolderInCurrentSpace(in: windowState)
            },
            createGitHubIssuesFolderInCurrentSpace: { [folderCommand] windowState in
                folderCommand.createGitHubIssuesFolderInCurrentSpace(in: windowState)
            },
            unloadShortcutPin: { [shortcutPinUnload] pin, windowState in
                shortcutPinUnload.unloadShortcutPin(pin, in: windowState)
            },
            unloadShortcutPins: { [shortcutPinUnload] pins, windowState in
                shortcutPinUnload.unloadShortcutPins(pins, in: windowState)
            }
        )
    }
}
