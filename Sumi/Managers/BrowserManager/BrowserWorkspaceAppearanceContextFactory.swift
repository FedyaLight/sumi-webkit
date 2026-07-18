import Foundation
import SumiDomain

@MainActor
final class BrowserWorkspaceAppearanceContextFactory {
    private let spaces: TabSpaceCollectionStateOwner
    private let windows: WindowRegistry
    private let transitions: BrowserWorkspaceThemeTransitionOwner
    private let persistence: TabStructuralPersistenceService
    private let modal: BrowserNativeModalTransaction

    init(
        spaces: TabSpaceCollectionStateOwner,
        windows: WindowRegistry,
        transitions: BrowserWorkspaceThemeTransitionOwner,
        persistence: TabStructuralPersistenceService,
        modal: BrowserNativeModalTransaction
    ) {
        self.spaces = spaces
        self.windows = windows
        self.transitions = transitions
        self.persistence = persistence
        self.modal = modal
    }

    func space(with id: UUID?) -> Space? {
        id.flatMap { spaces.space(with: $0) }
    }

    func make(
        currentSpaceOverride: Space? = nil,
        presentPicker: @escaping @MainActor (
            WorkspaceThemePickerSession,
            BrowserWindowState
        ) -> Void
    ) -> WorkspaceAppearanceService.Context {
        WorkspaceAppearanceService.Context(
            currentSpace: { [spaces] in
                currentSpaceOverride ?? spaces.currentSpace
            },
            spaceLookup: { [spaces] spaceID in
                spaces.spaces.first(where: { $0.id == spaceID })
            },
            windowRegistry: { [windows] in windows },
            commitWorkspaceTheme: { [transitions] theme, windowState in
                transitions.commitWorkspaceTheme(theme, for: windowState)
            },
            syncWorkspaceThemeAcrossWindows: { [transitions] space, animate in
                transitions.syncWorkspaceThemeAcrossWindows(
                    for: space,
                    animate: animate
                )
            },
            scheduleStructuralPersistence: { [persistence] in
                persistence.markAllSpacesStructurallyDirty()
                persistence.scheduleStructuralPersistence()
            },
            presentPicker: presentPicker,
            presentNotice: { [modal] notice, source in
                _ = modal.present(.notice(notice), source: source)
            }
        )
    }
}
