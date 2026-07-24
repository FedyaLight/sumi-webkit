import Foundation

/// Builds the SwiftUI command-palette context from explicit browser capabilities.
/// The factory does not locate services through `BrowserManager`.
@MainActor
final class CommandPaletteBrowserContextFactory {
    private let currentProfileId: @MainActor () -> UUID?
    private let faviconContext: @MainActor () -> CommandPaletteFaviconContext
    private let spaces: CommandPaletteSpaceCatalog
    private let extensions: CommandPaletteExtensionCatalog
    private let makeSearchSession:
        @MainActor () -> CommandPaletteSearchSessionOwner
    private let deleteHistory: @MainActor (HistoryQuery) async -> Void
    private let presentation: CommandPalettePresentationService
    private let commit: CommandPaletteCommitService

    init(
        currentProfileId: @escaping @MainActor () -> UUID?,
        faviconContext: @escaping @MainActor () -> CommandPaletteFaviconContext,
        spaces: CommandPaletteSpaceCatalog,
        extensions: CommandPaletteExtensionCatalog,
        makeSearchSession:
            @escaping @MainActor () -> CommandPaletteSearchSessionOwner,
        deleteHistory: @escaping @MainActor (HistoryQuery) async -> Void,
        presentation: CommandPalettePresentationService,
        commit: CommandPaletteCommitService
    ) {
        self.currentProfileId = currentProfileId
        self.faviconContext = faviconContext
        self.spaces = spaces
        self.extensions = extensions
        self.makeSearchSession = makeSearchSession
        self.deleteHistory = deleteHistory
        self.presentation = presentation
        self.commit = commit
    }

    var context: CommandPaletteBrowserContext {
        CommandPaletteBrowserContext(
            currentProfileId: currentProfileId(),
            favicon: faviconContext(),
            spaces: spaces,
            extensions: extensions,
            makeSearchSession: makeSearchSession,
            updateDraft: { [presentation] windowState, text in
                presentation.updateDraft(in: windowState, text: text)
            },
            dismiss: { [presentation] windowState, preserveDraft in
                presentation.dismiss(
                    in: windowState,
                    preserveDraft: preserveDraft
                )
            },
            deleteHistory: deleteHistory,
            commitNavigation: { [commit] urlString, windowState in
                commit.commitNavigation(to: urlString, in: windowState)
            },
            commitActivation: { [commit] activation, windowState in
                commit.commitActivation(activation, in: windowState)
            }
        )
    }
}
