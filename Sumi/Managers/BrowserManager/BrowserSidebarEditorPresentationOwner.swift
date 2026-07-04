import Foundation

@MainActor
final class BrowserSidebarEditorPresentationOwner {
    struct Dependencies {
        let sidebarPosition: @MainActor () -> SidebarPosition
        let settings: @MainActor () -> SumiSettingsService
        let profiles: @MainActor () -> [Profile]
        let renameSpace: @MainActor (UUID, String) throws -> Void
        let updateSpaceIcon: @MainActor (UUID, String) throws -> Void
        let assignSpaceProfile: @MainActor (UUID, UUID) -> Void
        let renameFolder: @MainActor (UUID, String) -> Void
        let updateFolderIcon: @MainActor (UUID, String) -> Void
        let updateShortcutPin: @MainActor (ShortcutPin, String, URL, String?) -> Void
    }

    private let dependencies: Dependencies
    private let folderEditorPopoverPresenter: FolderEditorPopoverPresenter
    private let folderSearchPopoverPresenter: FolderSearchPopoverPresenter
    private let spaceEditorPopoverPresenter: SpaceEditorPopoverPresenter
    private let shortcutEditorPopoverPresenter: ShortcutEditorPopoverPresenter

    init(
        dependencies: Dependencies,
        folderEditorPopoverPresenter: FolderEditorPopoverPresenter = FolderEditorPopoverPresenter(),
        folderSearchPopoverPresenter: FolderSearchPopoverPresenter = FolderSearchPopoverPresenter(),
        spaceEditorPopoverPresenter: SpaceEditorPopoverPresenter = SpaceEditorPopoverPresenter(),
        shortcutEditorPopoverPresenter: ShortcutEditorPopoverPresenter = ShortcutEditorPopoverPresenter()
    ) {
        self.dependencies = dependencies
        self.folderEditorPopoverPresenter = folderEditorPopoverPresenter
        self.folderSearchPopoverPresenter = folderSearchPopoverPresenter
        self.spaceEditorPopoverPresenter = spaceEditorPopoverPresenter
        self.shortcutEditorPopoverPresenter = shortcutEditorPopoverPresenter
    }

    func showSpaceEditor(
        for space: Space,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        spaceEditorPopoverPresenter.present(
            space: space,
            in: windowState,
            themeContext: themeContext,
            presentationContext: SpaceEditorPopoverPresentationContext(
                sidebarPosition: dependencies.sidebarPosition(),
                profiles: dependencies.profiles(),
                settings: dependencies.settings(),
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
        folderEditorPopoverPresenter.present(
            folder: folder,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderEditorPopoverPresentationContext(
                sidebarPosition: dependencies.sidebarPosition(),
                settings: dependencies.settings(),
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
        folderSearchPopoverPresenter.present(
            request: request,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderSearchPopoverPresentationContext(
                sidebarPosition: dependencies.sidebarPosition(),
                settings: dependencies.settings()
            ),
            source: source
        )
    }

    func setFolderSearchAnchorHovered(
        folderID: UUID,
        in windowState: BrowserWindowState,
        hovering: Bool
    ) {
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
        shortcutEditorPopoverPresenter.present(
            pin: pin,
            in: windowState,
            themeContext: themeContext,
            presentationContext: ShortcutEditorPopoverPresentationContext(
                sidebarPosition: dependencies.sidebarPosition(),
                settings: dependencies.settings(),
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
                try dependencies.renameSpace(session.spaceID, session.trimmedName)
            }
            if session.icon != session.originalIcon {
                try dependencies.updateSpaceIcon(session.spaceID, session.icon)
            }
            if let profileID = session.profileID, profileID != session.originalProfileID {
                dependencies.assignSpaceProfile(session.spaceID, profileID)
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
            dependencies.renameFolder(session.folderID, session.trimmedName)
        }
        if session.icon != session.originalIcon {
            dependencies.updateFolderIcon(session.folderID, session.icon)
        }
    }

    func commitShortcutEditorSession(_ session: ShortcutLinkEditorSession) {
        guard session.hasChanges,
              let launchURL = session.normalizedURL
        else { return }

        dependencies.updateShortcutPin(
            session.pin,
            session.effectiveTitle,
            launchURL,
            session.iconAsset
        )
    }
}

extension BrowserSidebarEditorPresentationOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            sidebarPosition: { [weak browserManager] in
                browserManager?.sumiSettings?.sidebarPosition ?? .left
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings ?? SumiSettingsService()
            },
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
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
    }
}
