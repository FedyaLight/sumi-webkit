import Foundation

/// Builds the SwiftUI command-palette context from explicit browser capabilities.
/// The factory does not locate services through `BrowserManager`.
@MainActor
final class CommandPaletteBrowserContextFactory {
    private let currentProfileId: @MainActor () -> UUID?
    private let faviconContext: @MainActor () -> CommandPaletteFaviconContext
    private let spaces: CommandPaletteSpaceCatalog
    private let extensions: CommandPaletteExtensionCatalog
    private let sessionCommands: CommandPaletteSessionCommands

    init(
        currentProfileId: @escaping @MainActor () -> UUID?,
        faviconContext: @escaping @MainActor () -> CommandPaletteFaviconContext,
        spaces: CommandPaletteSpaceCatalog,
        extensions: CommandPaletteExtensionCatalog,
        sessionCommands: CommandPaletteSessionCommands
    ) {
        self.currentProfileId = currentProfileId
        self.faviconContext = faviconContext
        self.spaces = spaces
        self.extensions = extensions
        self.sessionCommands = sessionCommands
    }

    var context: CommandPaletteBrowserContext {
        CommandPaletteBrowserContext(
            currentProfileId: currentProfileId(),
            favicon: faviconContext(),
            spaces: spaces,
            extensions: extensions,
            makeSearchSession: { [sessionCommands] in
                sessionCommands.makeSearchSession()
            },
            updateDraft: { [sessionCommands] windowState, text in
                sessionCommands.updateDraft(in: windowState, text: text)
            },
            dismiss: { [sessionCommands] windowState, preserveDraft in
                sessionCommands.dismiss(
                    in: windowState,
                    preserveDraft: preserveDraft
                )
            },
            deleteHistory: { [sessionCommands] query in
                await sessionCommands.deleteHistory(query)
            },
            commitNavigation: { [sessionCommands] urlString, windowState in
                sessionCommands.commitNavigation(
                    to: urlString,
                    in: windowState
                )
            },
            commitActivation: { [sessionCommands] activation, windowState in
                sessionCommands.commitActivation(activation, in: windowState)
            }
        )
    }
}
