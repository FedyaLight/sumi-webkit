import Foundation

@MainActor
final class SidebarSpaceEditorPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator
    private let profiles: ProfileManager
    private let spaces: SidebarSpaceLifecycle
    private let profileTransitions: SpaceProfileTransitionService
    private let presenter: SpaceEditorPopoverPresenter

    init(
        settings: BrowserSettingsAttachmentCoordinator,
        profiles: ProfileManager,
        spaces: SidebarSpaceLifecycle,
        profileTransitions: SpaceProfileTransitionService,
        presenter: SpaceEditorPopoverPresenter
    ) {
        self.settings = settings
        self.profiles = profiles
        self.spaces = spaces
        self.profileTransitions = profileTransitions
        self.presenter = presenter
    }

    func show(
        space: Space,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings.settings else { return }
        presenter.present(
            space: space,
            in: windowState,
            themeContext: themeContext,
            presentationContext: SpaceEditorPopoverPresentationContext(
                sidebarPosition: settings.sidebarPosition,
                profiles: profiles.profiles,
                settings: settings,
                commit: { [weak self] in self?.commit($0) }
            ),
            source: source
        )
    }

    func commit(_ session: SpaceEditorSession) {
        guard session.canCommit, session.hasChanges else { return }
        do {
            if session.trimmedName != session.originalName {
                try spaces.renameSpace(
                    session.spaceID,
                    to: session.trimmedName
                )
            }
            if session.icon != session.originalIcon {
                try spaces.updateSpaceIcon(
                    session.spaceID,
                    to: session.icon
                )
            }
            if let profileID = session.profileID,
               profileID != session.originalProfileID {
                profileTransitions.start(
                    spaceID: session.spaceID,
                    profileID: profileID
                )
            }
        } catch {
            RuntimeDiagnostics.emit(
                "⚠️ Failed to update space \(session.spaceID.uuidString):",
                error
            )
        }
    }
}
