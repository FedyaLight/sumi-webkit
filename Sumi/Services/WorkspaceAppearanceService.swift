import SwiftUI

@MainActor
final class WorkspaceThemePickerSession: ObservableObject, Identifiable {
    let id: UUID
    let spaceId: UUID
    let hostWindowID: UUID
    let originalTheme: WorkspaceTheme
    let presentationSource: SidebarTransientPresentationSource?
    let transientSessionToken: SidebarTransientSessionToken?
    @Published var draftTheme: WorkspaceTheme
    var commitsOnDismiss = false

    init(
        id: UUID = UUID(),
        spaceId: UUID,
        hostWindowID: UUID,
        originalTheme: WorkspaceTheme,
        presentationSource: SidebarTransientPresentationSource? = nil,
        transientSessionToken: SidebarTransientSessionToken? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.hostWindowID = hostWindowID
        self.originalTheme = originalTheme
        self.presentationSource = presentationSource
        self.transientSessionToken = transientSessionToken
        self.draftTheme = originalTheme
    }

    var hasPendingChanges: Bool {
        draftTheme != originalTheme
    }
}

@MainActor
final class WorkspaceAppearanceService {
    struct Context {
        let currentSpace: @MainActor () -> Space?
        let spaceLookup: @MainActor (UUID) -> Space?
        let windowRegistry: @MainActor () -> WindowRegistry?
        let commitWorkspaceTheme: @MainActor (WorkspaceTheme, BrowserWindowState) -> Void
        let syncWorkspaceThemeAcrossWindows: @MainActor (Space, Bool) -> Void
        let scheduleStructuralPersistence: @MainActor () -> Void
        let presentPicker: @MainActor (WorkspaceThemePickerSession) -> Void
        let showDialog: @MainActor (AnyView, SidebarTransientPresentationSource?) -> Void
        let closeDialog: @MainActor () -> Void
    }

    func showGradientEditor(
        using context: Context,
        preferredSource: SidebarTransientPresentationSource? = nil
    ) {
        guard let space = context.currentSpace() else {
            context.showDialog(
                AnyView(
                    StandardDialog(
                        header: {
                            DialogHeader(
                                icon: "paintpalette",
                                title: "No Space Available",
                                subtitle: "Create a space to customize its gradient."
                            )
                        },
                        content: {
                            Color.clear.frame(height: 0)
                        },
                        footer: {
                            DialogFooter(rightButtons: [
                                DialogButton(text: "OK", variant: .primary) {
                                    context.closeDialog()
                                }
                            ])
                        }
                    )
                ),
                preferredSource
            )
            return
        }

        guard let previewWindow = previewWindow(
            for: space,
            preferredWindowID: preferredSource?.windowID,
            using: context
        ) else {
            context.showDialog(
                AnyView(
                    StandardDialog(
                        header: {
                            DialogHeader(
                                icon: "paintpalette",
                                title: "No Browser Window",
                                subtitle: "Open a browser window for this workspace to edit its theme."
                            )
                        },
                        content: {
                            Color.clear.frame(height: 0)
                        },
                        footer: {
                            DialogFooter(rightButtons: [
                                DialogButton(text: "OK", variant: .primary) {
                                    context.closeDialog()
                                }
                            ])
                        }
                    )
                ),
                preferredSource
            )
            return
        }

        let transientSessionToken = preferredSource.flatMap {
            $0.coordinator?.beginSession(
                kind: .themePicker,
                source: $0,
                path: "WorkspaceAppearanceService.showGradientEditor"
            )
        }

        context.presentPicker(
            WorkspaceThemePickerSession(
                spaceId: space.id,
                hostWindowID: previewWindow.id,
                originalTheme: space.workspaceTheme,
                presentationSource: preferredSource,
                transientSessionToken: transientSessionToken
            )
        )
        previewWindow.window?.makeKeyAndOrderFront(nil)
    }

    func previewGradientEditorSession(
        _ session: WorkspaceThemePickerSession,
        using context: Context
    ) {
        guard let space = context.spaceLookup(session.spaceId),
              let previewWindow = previewWindow(
                for: space,
                preferredWindowID: session.hostWindowID,
                using: context
              )
        else { return }

        context.commitWorkspaceTheme(session.draftTheme, previewWindow)
    }

    func finalizeDismissedGradientEditorSession(
        _ session: WorkspaceThemePickerSession,
        using context: Context
    ) {
        guard let space = context.spaceLookup(session.spaceId) else { return }

        if session.commitsOnDismiss, session.hasPendingChanges {
            space.workspaceTheme = session.draftTheme
            context.syncWorkspaceThemeAcrossWindows(space, false)
            context.scheduleStructuralPersistence()
            return
        }

        guard let previewWindow = previewWindow(
            for: space,
            preferredWindowID: session.hostWindowID,
            using: context
        ) else { return }

        context.commitWorkspaceTheme(space.workspaceTheme, previewWindow)
    }

    private func previewWindow(
        for space: Space,
        preferredWindowID: UUID?,
        using context: Context
    ) -> BrowserWindowState? {
        guard let windowRegistry = context.windowRegistry() else { return nil }

        if let preferredWindowID,
           let preferredWindow = windowRegistry.windows[preferredWindowID],
           !preferredWindow.isIncognito,
           preferredWindow.currentSpaceId == space.id {
            return preferredWindow
        }

        if let activeWindow = windowRegistry.activeWindow,
           !activeWindow.isIncognito,
           activeWindow.currentSpaceId == space.id {
            return activeWindow
        }

        return windowRegistry.windows.values.first(where: {
            !$0.isIncognito && $0.currentSpaceId == space.id
        })
    }
}
