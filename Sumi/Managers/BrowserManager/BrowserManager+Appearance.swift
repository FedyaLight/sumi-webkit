import SwiftUI

@MainActor
extension BrowserManager {
    func showGradientEditor() {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(using: makeWorkspaceAppearanceContext())
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(
            using: makeWorkspaceAppearanceContext(),
            preferredSource: source
        )
    }

    func showGradientEditor(for space: Space, source: SidebarTransientPresentationSource) {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(
            using: makeWorkspaceAppearanceContext(currentSpaceOverride: space),
            preferredSource: source
        )
    }

    func previewWorkspaceThemePickerDraft(sessionID: UUID) {
        guard let session = workspaceThemePickerSession,
              session.id == sessionID
        else { return }

        workspaceAppearanceService.previewGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
    }

    func dismissWorkspaceThemePicker(sessionID: UUID) {
        guard let session = workspaceThemePickerSession,
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = true
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: true)
    }

    /// Dismisses the theme picker without committing the draft (e.g. another modal took focus).
    func dismissWorkspaceThemePickerDiscarding(sessionID: UUID) {
        guard let session = workspaceThemePickerSession,
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = false
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: false)
    }

    /// Discards any open workspace theme picker session (used before presenting app-wide modals).
    func dismissThemePickerDiscardingIfNeeded() {
        guard let session = workspaceThemePickerSession else { return }
        dismissWorkspaceThemePickerDiscarding(sessionID: session.id)
    }

    /// Commits and closes any open workspace theme picker session.
    func dismissThemePickerCommittingIfNeeded() {
        guard let session = workspaceThemePickerSession else { return }
        dismissWorkspaceThemePicker(sessionID: session.id)
    }

    func finalizeWorkspaceThemePickerDismiss(_ session: WorkspaceThemePickerSession) {
        workspaceAppearanceService.finalizeDismissedGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
        if workspaceThemePickerSession?.id == session.id {
            workspaceThemePickerSession = nil
        }
    }

    private func presentWorkspaceThemePicker(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState
    ) {
        workspaceThemePickerSession = session
        workspaceThemePickerPopoverPresenter.present(
            session,
            in: windowState,
            runtime: makeWorkspaceThemePickerPopoverRuntime()
        )
    }

    private func makeWorkspaceThemePickerPopoverRuntime() -> WorkspaceThemePickerPopoverRuntime {
        WorkspaceThemePickerPopoverRuntime(
            settings: { [weak self] in
                self?.sumiSettings ?? SumiSettingsService()
            },
            previewDraft: { [weak self] sessionID in
                self?.previewWorkspaceThemePickerDraft(sessionID: sessionID)
            },
            finalizeDismiss: { [weak self] session in
                self?.finalizeWorkspaceThemePickerDismiss(session)
            }
        )
    }

    private func closeWorkspaceThemePickerIfPresented() -> Bool {
        guard let session = workspaceThemePickerSession,
              workspaceThemePickerPopoverPresenter.hasActiveSession
        else { return false }

        dismissWorkspaceThemePicker(sessionID: session.id)
        return true
    }

    private func makeWorkspaceAppearanceContext(
        currentSpaceOverride: Space? = nil
    ) -> WorkspaceAppearanceService.Context {
        WorkspaceAppearanceService.Context(
            currentSpace: { [weak self] in
                currentSpaceOverride ?? self?.tabManager.currentSpace
            },
            spaceLookup: { [weak self] spaceID in
                self?.tabManager.spaces.first(where: { $0.id == spaceID })
            },
            windowRegistry: { [weak self] in
                self?.windowRegistry
            },
            commitWorkspaceTheme: { [weak self] theme, windowState in
                self?.commitWorkspaceTheme(theme, for: windowState)
            },
            syncWorkspaceThemeAcrossWindows: { [weak self] space, animate in
                self?.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
            },
            scheduleStructuralPersistence: { [weak self] in
                self?.tabManager.markAllSpacesStructurallyDirty()
                self?.tabManager.scheduleStructuralPersistence()
            },
            presentPicker: { [weak self] session, windowState in
                self?.presentWorkspaceThemePicker(session, in: windowState)
            },
            presentNotice: { [weak self] notice, source in
                self?.presentNoticeSheet(notice, source: source)
            }
        )
    }
}
