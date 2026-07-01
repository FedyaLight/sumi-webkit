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
    let commandRouting: BrowserSidebarCommandRoutingOwner

    init(browserManager: BrowserManager) {
        editorPresentation = BrowserSidebarEditorPresentationOwner(
            dependencies: .live(browserManager: browserManager)
        )
        chromeCommand = BrowserSidebarChromeCommandOwner(
            dependencies: .live(browserManager: browserManager)
        )
        shortcutPromotion = BrowserSidebarShortcutPromotionOwner(
            dependencies: .live(browserManager: browserManager)
        )
        folderCommand = BrowserSidebarFolderCommandOwner(
            dependencies: .live(browserManager: browserManager)
        )
        tabCommand = BrowserSidebarTabCommandOwner(
            dependencies: .live(browserManager: browserManager)
        )
        splitShortcutRouting = BrowserSidebarSplitShortcutRoutingOwner(
            dependencies: .live(browserManager: browserManager)
        )
        spaceTransitionRouting = BrowserSpaceTransitionRoutingOwner(
            dependencies: .live(browserManager: browserManager)
        )
        commandRouting = BrowserSidebarCommandRoutingOwner(
            dependencies: .live(browserManager: browserManager)
        )
    }

    func makeSpaceTransitionActions() -> SidebarSpaceTransitionActions {
        spaceTransitionRouting.makeActions()
    }

    func makeCommandActions() -> SidebarBrowserCommandActions {
        commandRouting.makeActions()
    }
}
