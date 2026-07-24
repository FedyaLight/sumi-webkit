import Foundation

@MainActor
struct CommandPaletteFaviconContext {
    let partition: SumiFaviconPartition
    let imageReader: any BrowserFaviconImageReading
    let prefetch: any BrowserFaviconPrefetchScheduling
}

@MainActor
final class CommandPaletteBrowserContext {
    let currentProfileId: UUID?
    let favicon: CommandPaletteFaviconContext
    let spaces: CommandPaletteSpaceCatalog
    let extensions: CommandPaletteExtensionCatalog

    private let makeSearchSessionHandler: () -> CommandPaletteSearchSessionOwner
    private let updateDraftHandler: (BrowserWindowState, String) -> Void
    private let dismissHandler: (BrowserWindowState, Bool) -> Void
    private let deleteHistoryHandler: (HistoryQuery) async -> Void
    private let commitNavigationHandler: (String, BrowserWindowState) -> Void
    private let commitActivationHandler: (
        CommandPaletteRow.Activation,
        BrowserWindowState
    ) -> Void

    init(
        currentProfileId: UUID?,
        favicon: CommandPaletteFaviconContext,
        spaces: CommandPaletteSpaceCatalog,
        extensions: CommandPaletteExtensionCatalog,
        makeSearchSession: @escaping () -> CommandPaletteSearchSessionOwner,
        updateDraft: @escaping (BrowserWindowState, String) -> Void,
        dismiss: @escaping (BrowserWindowState, Bool) -> Void,
        deleteHistory: @escaping (HistoryQuery) async -> Void,
        commitNavigation: @escaping (String, BrowserWindowState) -> Void,
        commitActivation: @escaping (
            CommandPaletteRow.Activation,
            BrowserWindowState
        ) -> Void
    ) {
        self.currentProfileId = currentProfileId
        self.favicon = favicon
        self.spaces = spaces
        self.extensions = extensions
        self.makeSearchSessionHandler = makeSearchSession
        self.updateDraftHandler = updateDraft
        self.dismissHandler = dismiss
        self.deleteHistoryHandler = deleteHistory
        self.commitNavigationHandler = commitNavigation
        self.commitActivationHandler = commitActivation
    }

    func makeSearchSession() -> CommandPaletteSearchSessionOwner {
        makeSearchSessionHandler()
    }

    func updateCommandPaletteDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        updateDraftHandler(windowState, text)
    }

    func dismissCommandPalette(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        dismissHandler(windowState, preserveDraft)
    }

    func deleteHistory(_ query: HistoryQuery) async {
        await deleteHistoryHandler(query)
    }

    func commitCommandPaletteNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        commitNavigationHandler(urlString, windowState)
    }

    func commitCommandPaletteActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState
    ) {
        commitActivationHandler(activation, windowState)
    }
}
