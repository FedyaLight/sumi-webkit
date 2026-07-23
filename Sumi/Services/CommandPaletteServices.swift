/// Behavior-free command-palette capability group. Presentation state, commit
/// routing, and UI-context construction remain independently testable.
@MainActor
struct CommandPaletteServices {
    let presentation: CommandPalettePresentationService
    let commit: CommandPaletteCommitService
    let browserContext: CommandPaletteBrowserContextFactory
}
