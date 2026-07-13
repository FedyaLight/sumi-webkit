import Foundation

@MainActor
final class BrowserSidebarEditorPresentationOwner {
    private let sidebarPosition: @MainActor () -> SidebarPosition
    private let settings: @MainActor () -> SumiSettingsService?
    private let profiles: @MainActor () -> [Profile]
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let renameSpace: @MainActor (UUID, String) throws -> Void
    private let updateSpaceIcon: @MainActor (UUID, String) throws -> Void
    private let assignSpaceProfile: @MainActor (UUID, UUID) -> Void
    private let renameFolder: @MainActor (UUID, String) -> Void
    private let updateFolderIcon: @MainActor (UUID, String) -> Void
    private let updateShortcutPin: @MainActor (ShortcutPin, String, URL, String?) -> Void
    private let folderEditorPopoverPresenter: FolderEditorPopoverPresenter
    private let folderSearchPopoverPresenter: FolderSearchPopoverPresenter
    private let spaceEditorPopoverPresenter: SpaceEditorPopoverPresenter
    private let shortcutEditorPopoverPresenter: ShortcutEditorPopoverPresenter

    init(
        sidebarPosition: @escaping @MainActor () -> SidebarPosition,
        settings: @escaping @MainActor () -> SumiSettingsService?,
        profiles: @escaping @MainActor () -> [Profile],
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        sidebarHostRecoveryCoordinator: @escaping @MainActor () -> SidebarHostRecoveryHandling,
        renameSpace: @escaping @MainActor (UUID, String) throws -> Void,
        updateSpaceIcon: @escaping @MainActor (UUID, String) throws -> Void,
        assignSpaceProfile: @escaping @MainActor (UUID, UUID) -> Void,
        renameFolder: @escaping @MainActor (UUID, String) -> Void,
        updateFolderIcon: @escaping @MainActor (UUID, String) -> Void,
        updateShortcutPin: @escaping @MainActor (ShortcutPin, String, URL, String?) -> Void,
        folderEditorPopoverPresenter: FolderEditorPopoverPresenter? = nil,
        folderSearchPopoverPresenter: FolderSearchPopoverPresenter? = nil,
        spaceEditorPopoverPresenter: SpaceEditorPopoverPresenter? = nil,
        shortcutEditorPopoverPresenter: ShortcutEditorPopoverPresenter? = nil
    ) {
        self.sidebarPosition = sidebarPosition
        self.settings = settings
        self.profiles = profiles
        self.windowRegistry = windowRegistry
        self.renameSpace = renameSpace
        self.updateSpaceIcon = updateSpaceIcon
        self.assignSpaceProfile = assignSpaceProfile
        self.renameFolder = renameFolder
        self.updateFolderIcon = updateFolderIcon
        self.updateShortcutPin = updateShortcutPin
        let recovery = sidebarHostRecoveryCoordinator()
        self.folderEditorPopoverPresenter = folderEditorPopoverPresenter
            ?? FolderEditorPopoverPresenter(sidebarRecoveryCoordinator: recovery)
        self.folderSearchPopoverPresenter = folderSearchPopoverPresenter
            ?? FolderSearchPopoverPresenter(sidebarRecoveryCoordinator: recovery)
        self.spaceEditorPopoverPresenter = spaceEditorPopoverPresenter
            ?? SpaceEditorPopoverPresenter(sidebarRecoveryCoordinator: recovery)
        self.shortcutEditorPopoverPresenter = shortcutEditorPopoverPresenter
            ?? ShortcutEditorPopoverPresenter(sidebarRecoveryCoordinator: recovery)
        let registry = windowRegistry()
        self.folderEditorPopoverPresenter.windowRegistry = registry
        self.folderSearchPopoverPresenter.windowRegistry = registry
        self.spaceEditorPopoverPresenter.windowRegistry = registry
        self.shortcutEditorPopoverPresenter.windowRegistry = registry
    }

    private func syncPresenterRegistries() {
        let registry = windowRegistry()
        folderEditorPopoverPresenter.windowRegistry = registry
        folderSearchPopoverPresenter.windowRegistry = registry
        spaceEditorPopoverPresenter.windowRegistry = registry
        shortcutEditorPopoverPresenter.windowRegistry = registry
    }

    func showSpaceEditor(
        for space: Space,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings() else { return }
        syncPresenterRegistries()
        spaceEditorPopoverPresenter.present(
            space: space,
            in: windowState,
            themeContext: themeContext,
            presentationContext: SpaceEditorPopoverPresentationContext(
                sidebarPosition: sidebarPosition(),
                profiles: profiles(),
                settings: settings,
                commit: { [weak self] session in
                    self?.commitSpaceEditorSession(session)
                }
            ),
            source: source
        )
    }

    func showFolderEditor(
        for folder: TabFolder,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings() else { return }
        syncPresenterRegistries()
        folderEditorPopoverPresenter.present(
            folder: folder,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderEditorPopoverPresentationContext(
                sidebarPosition: sidebarPosition(),
                settings: settings,
                commit: { [weak self] session in
                    self?.commitFolderEditorSession(session)
                }
            ),
            source: source
        )
    }

    func showFolderSearchPopover(
        request: FolderSearchPopoverRequest,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings() else { return }
        syncPresenterRegistries()
        folderSearchPopoverPresenter.present(
            request: request,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderSearchPopoverPresentationContext(
                sidebarPosition: sidebarPosition(),
                settings: settings
            ),
            source: source
        )
    }

    func setFolderSearchAnchorHovered(
        folderID: UUID,
        in windowState: BrowserWindowState,
        hovering: Bool
    ) {
        syncPresenterRegistries()
        folderSearchPopoverPresenter.setAnchorHovered(
            folderID: folderID,
            in: windowState,
            hovering: hovering
        )
    }

    func showShortcutEditor(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings() else { return }
        syncPresenterRegistries()
        shortcutEditorPopoverPresenter.present(
            pin: pin,
            in: windowState,
            themeContext: themeContext,
            presentationContext: ShortcutEditorPopoverPresentationContext(
                sidebarPosition: sidebarPosition(),
                settings: settings,
                commit: { [weak self] session in
                    self?.commitShortcutEditorSession(session)
                }
            ),
            source: source
        )
    }

    func commitSpaceEditorSession(_ session: SpaceEditorSession) {
        guard session.canCommit, session.hasChanges else { return }

        do {
            if session.trimmedName != session.originalName {
                try renameSpace(session.spaceID, session.trimmedName)
            }
            if session.icon != session.originalIcon {
                try updateSpaceIcon(session.spaceID, session.icon)
            }
            if let profileID = session.profileID, profileID != session.originalProfileID {
                assignSpaceProfile(session.spaceID, profileID)
            }
        } catch {
            RuntimeDiagnostics.emit("⚠️ Failed to update space \(session.spaceID.uuidString):", error)
        }
    }

    func commitFolderEditorSession(_ session: FolderEditorSession) {
        guard session.canCommit,
              session.hasChanges
        else { return }

        if session.trimmedName != session.originalName {
            renameFolder(session.folderID, session.trimmedName)
        }
        if session.icon != session.originalIcon {
            updateFolderIcon(session.folderID, session.icon)
        }
    }

    func commitShortcutEditorSession(_ session: ShortcutLinkEditorSession) {
        guard session.hasChanges,
              let launchURL = session.normalizedURL
        else { return }

        updateShortcutPin(
            session.pin,
            session.effectiveTitle,
            launchURL,
            session.iconAsset
        )
    }
}
