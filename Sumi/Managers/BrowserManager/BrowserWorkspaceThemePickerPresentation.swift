import Foundation

@MainActor
final class BrowserWorkspaceThemePickerPresentation {
    let presenter: WorkspaceThemePickerPopoverPresenter

    private let state: BrowserWorkspaceThemePickerSessionState
    private let windows: WindowRegistry
    private let settings: BrowserSettingsState

    init(
        state: BrowserWorkspaceThemePickerSessionState,
        windows: WindowRegistry,
        settings: BrowserSettingsState,
        recovery: SidebarHostRecoveryHandling
    ) {
        self.state = state
        self.windows = windows
        self.settings = settings
        self.presenter = WorkspaceThemePickerPopoverPresenter(
            sidebarRecoveryCoordinator: recovery
        )
    }

    var session: WorkspaceThemePickerSession? {
        state.session
    }

    var hasActiveSession: Bool {
        presenter.hasActiveSession
    }

    func present(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState,
        previewDraft: @escaping @MainActor (UUID) -> Void,
        finalizeDismiss: @escaping @MainActor (WorkspaceThemePickerSession) -> Void
    ) {
        state.present(session)
        presenter.windowRegistry = windows
        presenter.present(
            session,
            in: windowState,
            runtime: WorkspaceThemePickerPopoverRuntime(
                settings: { [settings] in settings.settings },
                previewDraft: previewDraft,
                finalizeDismiss: finalizeDismiss
            )
        )
    }

    func close(sessionID: UUID, committing: Bool) {
        guard let session = state.session,
              session.id == sessionID else {
            return
        }
        session.commitsOnDismiss = committing
        presenter.close(sessionID: sessionID, committing: committing)
    }

    func clear(_ session: WorkspaceThemePickerSession) {
        state.clear(session)
    }
}
