import SwiftUI

/// Presents the workspace gradient/theme editor and manages its picker
/// session lifecycle, owning `WorkspaceAppearanceService` and the picker
/// popover presenter.
@MainActor
final class BrowserWorkspaceThemeEditorOwner {
    struct Dependencies {
        let pickerSession: @MainActor () -> WorkspaceThemePickerSession?
        let setPickerSession: @MainActor (WorkspaceThemePickerSession?) -> Void
        let currentSpace: @MainActor () -> Space?
        let spaceLookup: @MainActor (UUID) -> Space?
        let windowRegistry: @MainActor () -> WindowRegistry?
        let commitWorkspaceTheme: @MainActor (WorkspaceTheme, BrowserWindowState) -> Void
        let syncWorkspaceThemeAcrossWindows: @MainActor (Space, Bool) -> Void
        let scheduleStructuralPersistence: @MainActor () -> Void
        let presentNotice: @MainActor (BrowserNoticeSheetModel, SidebarTransientPresentationSource?) -> Void
        let settings: @MainActor () -> SumiSettingsService?
    }

    let workspaceAppearanceService = WorkspaceAppearanceService()
    let workspaceThemePickerPopoverPresenter = WorkspaceThemePickerPopoverPresenter()
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

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
        guard let session = dependencies.pickerSession(),
              session.id == sessionID
        else { return }

        workspaceAppearanceService.previewGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
    }

    func dismissWorkspaceThemePicker(sessionID: UUID) {
        guard let session = dependencies.pickerSession(),
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = true
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: true)
    }

    /// Dismisses the theme picker without committing the draft (e.g. another modal took focus).
    func dismissWorkspaceThemePickerDiscarding(sessionID: UUID) {
        guard let session = dependencies.pickerSession(),
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = false
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: false)
    }

    /// Discards any open workspace theme picker session (used before presenting app-wide modals).
    func dismissThemePickerDiscardingIfNeeded() {
        guard let session = dependencies.pickerSession() else { return }
        dismissWorkspaceThemePickerDiscarding(sessionID: session.id)
    }

    /// Commits and closes any open workspace theme picker session.
    func dismissThemePickerCommittingIfNeeded() {
        guard let session = dependencies.pickerSession() else { return }
        dismissWorkspaceThemePicker(sessionID: session.id)
    }

    func finalizeWorkspaceThemePickerDismiss(_ session: WorkspaceThemePickerSession) {
        workspaceAppearanceService.finalizeDismissedGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
        if dependencies.pickerSession()?.id == session.id {
            dependencies.setPickerSession(nil)
        }
    }

    private func presentWorkspaceThemePicker(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState
    ) {
        dependencies.setPickerSession(session)
        workspaceThemePickerPopoverPresenter.present(
            session,
            in: windowState,
            runtime: makeWorkspaceThemePickerPopoverRuntime()
        )
    }

    private func makeWorkspaceThemePickerPopoverRuntime() -> WorkspaceThemePickerPopoverRuntime {
        WorkspaceThemePickerPopoverRuntime(
            settings: { [weak self] in
                self?.dependencies.settings() ?? SumiSettingsService()
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
        guard let session = dependencies.pickerSession(),
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
                currentSpaceOverride ?? self?.dependencies.currentSpace()
            },
            spaceLookup: { [weak self] spaceID in
                self?.dependencies.spaceLookup(spaceID)
            },
            windowRegistry: { [weak self] in
                self?.dependencies.windowRegistry()
            },
            commitWorkspaceTheme: { [weak self] theme, windowState in
                self?.dependencies.commitWorkspaceTheme(theme, windowState)
            },
            syncWorkspaceThemeAcrossWindows: { [weak self] space, animate in
                self?.dependencies.syncWorkspaceThemeAcrossWindows(space, animate)
            },
            scheduleStructuralPersistence: { [weak self] in
                self?.dependencies.scheduleStructuralPersistence()
            },
            presentPicker: { [weak self] session, windowState in
                self?.presentWorkspaceThemePicker(session, in: windowState)
            },
            presentNotice: { [weak self] notice, source in
                self?.dependencies.presentNotice(notice, source)
            }
        )
    }
}

extension BrowserWorkspaceThemeEditorOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            pickerSession: { [weak browserManager] in
                browserManager?.workspaceThemePickerSession
            },
            setPickerSession: { [weak browserManager] session in
                browserManager?.workspaceThemePickerSession = session
            },
            currentSpace: { [weak browserManager] in
                browserManager?.tabManager.currentSpace
            },
            spaceLookup: { [weak browserManager] spaceID in
                browserManager?.tabManager.spaces.first(where: { $0.id == spaceID })
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            commitWorkspaceTheme: { [weak browserManager] theme, windowState in
                browserManager?.workspaceThemeTransitionOwner.commitWorkspaceTheme(
                    theme,
                    for: windowState
                )
            },
            syncWorkspaceThemeAcrossWindows: { [weak browserManager] space, animate in
                browserManager?.workspaceThemeTransitionOwner.syncWorkspaceThemeAcrossWindows(
                    for: space,
                    animate: animate
                )
            },
            scheduleStructuralPersistence: { [weak browserManager] in
                browserManager?.tabManager.markAllSpacesStructurallyDirty()
                browserManager?.tabManager.scheduleStructuralPersistence()
            },
            presentNotice: { [weak browserManager] notice, source in
                browserManager?.nativeDialogPresentationOwner.presentNoticeSheet(notice, source: source)
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}
