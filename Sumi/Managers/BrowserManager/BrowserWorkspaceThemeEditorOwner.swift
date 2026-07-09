import SwiftUI

/// Presents the workspace gradient/theme editor and manages its picker
/// session lifecycle, owning `WorkspaceAppearanceService` and the picker
/// popover presenter.
@MainActor
final class BrowserWorkspaceThemeEditorOwner {
    let workspaceAppearanceService = WorkspaceAppearanceService()
    let workspaceThemePickerPopoverPresenter: WorkspaceThemePickerPopoverPresenter

    private let pickerSession: @MainActor () -> WorkspaceThemePickerSession?
    private let setPickerSession: @MainActor (WorkspaceThemePickerSession?) -> Void
    private let currentSpace: @MainActor () -> Space?
    private let spaceLookup: @MainActor (UUID) -> Space?
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let commitWorkspaceTheme: @MainActor (WorkspaceTheme, BrowserWindowState) -> Void
    private let syncWorkspaceThemeAcrossWindows: @MainActor (Space, Bool) -> Void
    private let scheduleStructuralPersistence: @MainActor () -> Void
    private let presentNotice: @MainActor (BrowserNoticeSheetModel, SidebarTransientPresentationSource?) -> Void
    private let settings: @MainActor () -> SumiSettingsService?

    init(
        pickerSession: @escaping @MainActor () -> WorkspaceThemePickerSession?,
        setPickerSession: @escaping @MainActor (WorkspaceThemePickerSession?) -> Void,
        currentSpace: @escaping @MainActor () -> Space?,
        spaceLookup: @escaping @MainActor (UUID) -> Space?,
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        sidebarHostRecoveryCoordinator: @escaping @MainActor () -> SidebarHostRecoveryHandling,
        commitWorkspaceTheme: @escaping @MainActor (WorkspaceTheme, BrowserWindowState) -> Void,
        syncWorkspaceThemeAcrossWindows: @escaping @MainActor (Space, Bool) -> Void,
        scheduleStructuralPersistence: @escaping @MainActor () -> Void,
        presentNotice: @escaping @MainActor (BrowserNoticeSheetModel, SidebarTransientPresentationSource?) -> Void,
        settings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.pickerSession = pickerSession
        self.setPickerSession = setPickerSession
        self.currentSpace = currentSpace
        self.spaceLookup = spaceLookup
        self.windowRegistry = windowRegistry
        self.commitWorkspaceTheme = commitWorkspaceTheme
        self.syncWorkspaceThemeAcrossWindows = syncWorkspaceThemeAcrossWindows
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
        self.presentNotice = presentNotice
        self.settings = settings
        self.workspaceThemePickerPopoverPresenter = WorkspaceThemePickerPopoverPresenter(
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator()
        )
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
        guard let session = pickerSession(),
              session.id == sessionID
        else { return }

        workspaceAppearanceService.previewGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
    }

    func dismissWorkspaceThemePicker(sessionID: UUID) {
        guard let session = pickerSession(),
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = true
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: true)
    }

    /// Dismisses the theme picker without committing the draft (e.g. another modal took focus).
    func dismissWorkspaceThemePickerDiscarding(sessionID: UUID) {
        guard let session = pickerSession(),
              session.id == sessionID
        else { return }

        session.commitsOnDismiss = false
        workspaceThemePickerPopoverPresenter.close(sessionID: session.id, committing: false)
    }

    /// Discards any open workspace theme picker session (used before presenting app-wide modals).
    func dismissThemePickerDiscardingIfNeeded() {
        guard let session = pickerSession() else { return }
        dismissWorkspaceThemePickerDiscarding(sessionID: session.id)
    }

    /// Commits and closes any open workspace theme picker session.
    func dismissThemePickerCommittingIfNeeded() {
        guard let session = pickerSession() else { return }
        dismissWorkspaceThemePicker(sessionID: session.id)
    }

    func finalizeWorkspaceThemePickerDismiss(_ session: WorkspaceThemePickerSession) {
        workspaceAppearanceService.finalizeDismissedGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
        if pickerSession()?.id == session.id {
            setPickerSession(nil)
        }
    }

    private func presentWorkspaceThemePicker(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState
    ) {
        setPickerSession(session)
        workspaceThemePickerPopoverPresenter.windowRegistry = windowRegistry()
        workspaceThemePickerPopoverPresenter.present(
            session,
            in: windowState,
            runtime: makeWorkspaceThemePickerPopoverRuntime()
        )
    }

    private func makeWorkspaceThemePickerPopoverRuntime() -> WorkspaceThemePickerPopoverRuntime {
        WorkspaceThemePickerPopoverRuntime(
            settings: { [weak self] in
                self?.settings() ?? SumiSettingsService()
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
        guard let session = pickerSession(),
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
                currentSpaceOverride ?? self?.currentSpace()
            },
            spaceLookup: { [weak self] spaceID in
                self?.spaceLookup(spaceID)
            },
            windowRegistry: { [weak self] in
                self?.windowRegistry()
            },
            commitWorkspaceTheme: { [weak self] theme, windowState in
                self?.commitWorkspaceTheme(theme, windowState)
            },
            syncWorkspaceThemeAcrossWindows: { [weak self] space, animate in
                self?.syncWorkspaceThemeAcrossWindows(space, animate)
            },
            scheduleStructuralPersistence: { [weak self] in
                self?.scheduleStructuralPersistence()
            },
            presentPicker: { [weak self] session, windowState in
                self?.presentWorkspaceThemePicker(session, in: windowState)
            },
            presentNotice: { [weak self] notice, source in
                self?.presentNotice(notice, source)
            }
        )
    }
}
