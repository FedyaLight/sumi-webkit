import Foundation
import SumiDomain

@MainActor
final class BrowserWorkspaceThemeEditorOwner {
    let workspaceAppearanceService: WorkspaceAppearanceService
    let workspaceThemePickerPopoverPresenter: WorkspaceThemePickerPopoverPresenter

    private let contexts: BrowserWorkspaceAppearanceContextFactory
    private let presentation: BrowserWorkspaceThemePickerPresentation

    init(
        workspaceAppearanceService: WorkspaceAppearanceService,
        contexts: BrowserWorkspaceAppearanceContextFactory,
        presentation: BrowserWorkspaceThemePickerPresentation
    ) {
        self.workspaceAppearanceService = workspaceAppearanceService
        self.contexts = contexts
        self.presentation = presentation
        self.workspaceThemePickerPopoverPresenter = presentation.presenter
    }

    func showGradientEditor() {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(using: makeContext())
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(
            using: makeContext(),
            preferredSource: source
        )
    }

    func showGradientEditor(
        for space: Space,
        source: SidebarTransientPresentationSource
    ) {
        guard !closeWorkspaceThemePickerIfPresented() else { return }
        workspaceAppearanceService.showGradientEditor(
            using: makeContext(currentSpaceOverride: space),
            preferredSource: source
        )
    }

    func previewWorkspaceThemePickerDraft(sessionID: UUID) {
        guard let session = presentation.session,
              session.id == sessionID else {
            return
        }
        workspaceAppearanceService.previewGradientEditorSession(
            session,
            using: makeContext()
        )
    }

    func dismissWorkspaceThemePicker(sessionID: UUID) {
        presentation.close(sessionID: sessionID, committing: true)
    }

    func dismissWorkspaceThemePickerDiscarding(sessionID: UUID) {
        presentation.close(sessionID: sessionID, committing: false)
    }

    func dismissThemePickerDiscardingIfNeeded() {
        guard let session = presentation.session else { return }
        dismissWorkspaceThemePickerDiscarding(sessionID: session.id)
    }

    func dismissThemePickerCommittingIfNeeded() {
        guard let session = presentation.session else { return }
        dismissWorkspaceThemePicker(sessionID: session.id)
    }

    func finalizeWorkspaceThemePickerDismiss(
        _ session: WorkspaceThemePickerSession
    ) {
        workspaceAppearanceService.finalizeDismissedGradientEditorSession(
            session,
            using: makeContext()
        )
        presentation.clear(session)
    }

    private func closeWorkspaceThemePickerIfPresented() -> Bool {
        guard let session = presentation.session,
              presentation.hasActiveSession else {
            return false
        }
        dismissWorkspaceThemePicker(sessionID: session.id)
        return true
    }

    private func makeContext(
        currentSpaceOverride: Space? = nil
    ) -> WorkspaceAppearanceService.Context {
        contexts.make(
            currentSpaceOverride: currentSpaceOverride,
            presentPicker: { [weak self] session, windowState in
                self?.present(session, in: windowState)
            }
        )
    }

    private func present(
        _ session: WorkspaceThemePickerSession,
        in windowState: BrowserWindowState
    ) {
        presentation.present(
            session,
            in: windowState,
            previewDraft: { [weak self] sessionID in
                self?.previewWorkspaceThemePickerDraft(sessionID: sessionID)
            },
            finalizeDismiss: { [weak self] session in
                self?.finalizeWorkspaceThemePickerDismiss(session)
            }
        )
    }
}
