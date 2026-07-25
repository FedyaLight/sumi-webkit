import Foundation

/// Everything the command palette can *do* to the browser: open a search
/// session, edit or dismiss the draft, prune history, and commit a destination.
/// `CommandPaletteBrowserContext` splits read state from behaviour, and this
/// role is the behaviour half, so the SwiftUI context factory assembles one
/// collaborator instead of bridging the presentation and commit services itself.
@MainActor
final class CommandPaletteSessionCommands {
    private let presentation: CommandPalettePresentationService
    private let commit: CommandPaletteCommitService
    private let makeSearchSessionHandler:
        @MainActor () -> CommandPaletteSearchSessionOwner
    private let deleteHistoryHandler: @MainActor (HistoryQuery) async -> Void

    init(
        presentation: CommandPalettePresentationService,
        commit: CommandPaletteCommitService,
        makeSearchSession:
            @escaping @MainActor () -> CommandPaletteSearchSessionOwner,
        deleteHistory: @escaping @MainActor (HistoryQuery) async -> Void
    ) {
        self.presentation = presentation
        self.commit = commit
        makeSearchSessionHandler = makeSearchSession
        deleteHistoryHandler = deleteHistory
    }

    func makeSearchSession() -> CommandPaletteSearchSessionOwner {
        makeSearchSessionHandler()
    }

    func updateDraft(in windowState: BrowserWindowState, text: String) {
        presentation.updateDraft(in: windowState, text: text)
    }

    func dismiss(in windowState: BrowserWindowState, preserveDraft: Bool) {
        presentation.dismiss(in: windowState, preserveDraft: preserveDraft)
    }

    func deleteHistory(_ query: HistoryQuery) async {
        await deleteHistoryHandler(query)
    }

    func commitNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        commit.commitNavigation(to: urlString, in: windowState)
    }

    func commitActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState
    ) {
        commit.commitActivation(activation, in: windowState)
    }
}
