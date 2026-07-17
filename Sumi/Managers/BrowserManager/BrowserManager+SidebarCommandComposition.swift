import Foundation

@MainActor
extension BrowserManager {
    func composeSidebarSpaceEditorPresentation() -> SidebarSpaceEditorPresentationService {
        let presenter = SpaceEditorPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        presenter.windowRegistry = windowRegistry
        return SidebarSpaceEditorPresentationService(
            settings: settingsAttachment,
            profiles: profileManager,
            spaces: sidebarSpaceLifecycle,
            profileTransitions: spaceProfileTransitions,
            presenter: presenter
        )
    }

    func composeSidebarFolderEditorPresentation() -> SidebarFolderEditorPresentationService {
        let presenter = FolderEditorPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        presenter.windowRegistry = windowRegistry
        return SidebarFolderEditorPresentationService(
            settings: settingsAttachment,
            folderCommands: sidebarFolderCommands,
            presenter: presenter
        )
    }

    func composeSidebarFolderSearchPresentation() -> SidebarFolderSearchPresentationService {
        let presenter = FolderSearchPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        presenter.windowRegistry = windowRegistry
        return SidebarFolderSearchPresentationService(
            settings: settingsAttachment,
            presenter: presenter
        )
    }

    func composeSidebarShortcutEditorPresentation() -> SidebarShortcutEditorPresentationService {
        let presenter = ShortcutEditorPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        presenter.windowRegistry = windowRegistry
        return SidebarShortcutEditorPresentationService(
            settings: settingsAttachment,
            pinCommands: sidebarPinCommands,
            faviconImages: dataServices.faviconCapabilities.images,
            presenter: presenter
        )
    }

    func composeSidebarShortcutPinUnloadOwner() -> BrowserShortcutPinUnloadOwner {
        BrowserShortcutPinUnloadOwner(
            shortcuts: shortcutPresentationOwner,
            close: shortcutLiveTabClose,
            notifications: notificationPresenter
        )
    }

    func composeSidebarSpaceTransitionRoutingOwner() -> BrowserSpaceTransitionRoutingOwner {
        BrowserSpaceTransitionRoutingOwner(
            splitFocus: splitShortcutFocus,
            spaceTransitions: windowSpaceTransitions,
            themeTransitions: chromeBundle.workspaceThemeTransitionOwner
        )
    }
}
