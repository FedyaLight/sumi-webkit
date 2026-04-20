import SwiftUI

@MainActor
extension BrowserManager {
    func showGradientEditor() {
        workspaceAppearanceService.showGradientEditor(using: makeWorkspaceAppearanceContext())
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        workspaceAppearanceService.showGradientEditor(
            using: makeWorkspaceAppearanceContext(),
            preferredSource: source
        )
    }

    func showGradientEditor(for space: Space, source: SidebarTransientPresentationSource) {
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
        workspaceThemePickerSession = nil
    }

    func finalizeWorkspaceThemePickerDismiss(_ session: WorkspaceThemePickerSession) {
        workspaceAppearanceService.finalizeDismissedGradientEditorSession(
            session,
            using: makeWorkspaceAppearanceContext()
        )
    }

    func applyGradientPresetToCurrentSpace(_ gradient: SpaceGradient) {
        workspaceAppearanceService.applyGradientPresetToCurrentSpace(
            gradient,
            using: makeWorkspaceAppearanceContext()
        )
    }

    func applyWorkspaceThemePresetToCurrentSpace(_ workspaceTheme: WorkspaceTheme) {
        workspaceAppearanceService.applyWorkspaceThemePresetToCurrentSpace(
            workspaceTheme,
            using: makeWorkspaceAppearanceContext()
        )
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
            persistSnapshot: { [weak self] in
                self?.tabManager.persistSnapshot()
            },
            presentPicker: { [weak self] session in
                self?.workspaceThemePickerSession = session
            },
            dismissPicker: { [weak self] in
                self?.workspaceThemePickerSession = nil
            },
            showDialog: { [weak self] dialog, source in
                if let source {
                    self?.showDialog(dialog, source: source)
                } else {
                    self?.showDialog(dialog)
                }
            },
            closeDialog: { [weak self] in
                self?.closeDialog()
            }
        )
    }
}
